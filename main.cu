// This version assigns correct edge labels to all bcc's

#include <string>
#include <vector>
#include <fstream>
#include <iostream>
#include <unordered_set>
#include <cstdint>
#include <random>
#include <algorithm>
#include <chrono>

#include <unistd.h>
#include <cuda_runtime.h>

#include "graph.hpp"
#include "timer.hpp"
#include "utility.hpp"

#include "bcc.cuh"
#include "lca.cuh"
#include "cut_vertex.cuh"
#include "cuda_utility.cuh"
#include "bcc_memory_utils.cuh"
#include "CommandLineParser.cuh"

namespace {

inline uint64_t pack_edge(int u, int v) {
    return (static_cast<uint64_t>(u) << 32) | static_cast<uint32_t>(v);
}

// Generates up to `batchSize` random edges not already present in the graph,
// mirroring the batch-generation logic of the CPU baseline (main.cpp).
std::vector<uint64_t> generate_batch_edges(
    const std::vector<int>& u_arr,
    const std::vector<int>& v_arr,
    int numVert,
    int batchSize) {

    std::vector<uint64_t> sorted_edges(u_arr.size());
    for (std::size_t i = 0; i < u_arr.size(); ++i) {
        int u = u_arr[i], v = v_arr[i];
        if (u > v) std::swap(u, v);
        sorted_edges[i] = pack_edge(u, v);
    }
    std::sort(sorted_edges.begin(), sorted_edges.end());

    auto edge_exists = [&](uint64_t e) {
        auto it = std::lower_bound(sorted_edges.begin(), sorted_edges.end(), e);
        return it != sorted_edges.end() && *it == e;
    };

    std::mt19937 gen(12345);
    std::uniform_int_distribution<int> dis(0, numVert - 1);
    constexpr int max_attempts = 100;

    std::vector<uint64_t> candidates;
    candidates.reserve(batchSize);

    for (int i = 0; i < batchSize; ++i) {
        for (int attempt = 0; attempt < max_attempts; ++attempt) {
            int u = dis(gen);
            int v = dis(gen);

            if (u == v) continue;
            if (u > v) std::swap(u, v);

            uint64_t e = pack_edge(u, v);
            if (!edge_exists(e)) {
                candidates.push_back(e);
                break;
            }
        }
    }

    std::sort(candidates.begin(), candidates.end());
    candidates.erase(std::unique(candidates.begin(), candidates.end()), candidates.end());
    return candidates;
}

} // namespace

void assign_edge_bcc(const std::vector<int>& U, const std::vector<int>& V, std::vector<int>& edge_bcc_num, const std::vector<int>& imp_bcc_num, const std::vector<int>& cut_vertex, const std::vector<int>& parent) {
	long numEdges = U.size();
	for(long i = 0; i < numEdges; ++i) {
		
		// case_1: both are non-cut_vertices
		int u = U[i];
		int v = V[i];
		if(!cut_vertex[u] and !cut_vertex[v]) {
			edge_bcc_num[i] = imp_bcc_num[u];
		}

		// case_2: both are cut_vertices
		else if(cut_vertex[u] and cut_vertex[v]) {
			if(parent[u] == v) {
				std::cout << "parent of u is v";
				// assign the bcc_num of child
				edge_bcc_num[i] = imp_bcc_num[u];
			} else if(parent[v] == u) {
				std::cout << "parent of v is u";
				edge_bcc_num[i] = imp_bcc_num[v];
			}
			else {
				std::cout << "Not a tree edge.";
				edge_bcc_num[i] = imp_bcc_num[u];
			}
		}

		// case_3: one vertex is cut_vertex and the other non_cut_vertex
		else {
			edge_bcc_num[i] = imp_bcc_num[!cut_vertex[u]? u : v];
		}
	}
}

int main(int argc, char* argv[]) {
	std::ios_base::sync_with_stdio(false);
	CommandLineParser cmdParser(argc, argv);
	const auto& args = cmdParser.getArgs();
		
	if (args.error) {
        std::cerr << CommandLineParser::help_msg << std::endl;
        exit(EXIT_FAILURE);
    }

	// Set the CUDA device
    CUDA_CHECK(cudaSetDevice(args.cudaDevice), "Unable to set device ");

	std::string filename = args.inputFile;
	std::cout <<"\n\nReading " << get_file_extension(filename) << " file.\n";
	Timer t1;
	undirected_graph G(filename);
	auto dur = t1.stop();
	// std::cout <<"Reading input and csr creation finished in: " << formatDuration(dur) << std::endl;
	t1.reset();

	bool write_output = args.write_output;
	// write_output = false;
	std::string output_path = args.output_directory;

	cudaFree(0);
	int numVert = G.numVert;
	long numEdges = G.u_arr.size();
	int batchSize = args.batchSize;

	gpu_bcc g_bcc_ds(numVert, numEdges, batchSize);
	// Copy the edge-list
	CUDA_CHECK(cudaMemcpy(g_bcc_ds.original_u, G.u_arr.data(), numEdges * sizeof(int), cudaMemcpyHostToDevice), 
    			"Unable to copy original_u array to device");
    CUDA_CHECK(cudaMemcpy(g_bcc_ds.original_v, G.v_arr.data(), numEdges * sizeof(int), cudaMemcpyHostToDevice),
    			"Unable to copy original_v array to device");

    // Copy the csr graph
    CUDA_CHECK(cudaMemcpy(g_bcc_ds.d_vertices, G.vertices.data(), G.vertices.size() * sizeof(long), cudaMemcpyHostToDevice), 
    			"Unable to copy csr_edge_offset array to device");
    CUDA_CHECK(cudaMemcpy(g_bcc_ds.d_edges, G.edges.data(), G.edges.size() * sizeof(int), cudaMemcpyHostToDevice),
    			"Unable to copy csr_neighbour array to device");

    // init data_structures
	g_bcc_ds.init(numVert, numEdges);

	// start cuda_bcc
    cuda_bcc(g_bcc_ds);

	// --------------------------------------------------------
	// Batch update: insert `batchSize` new random edges (not already
	// in the graph) and incrementally update the fundamental-cycle
	// state, connected components, and cut vertices, reusing the
	// spanning tree computed above.
	// --------------------------------------------------------

	if (batchSize > 0) {
		std::vector<uint64_t> batch_edges =
			generate_batch_edges(G.u_arr, G.v_arr, numVert, batchSize);

		std::cout << "\nRequested batch size: " << batchSize
				  << ", generated " << batch_edges.size()
				  << " distinct new edges\n";

		std::vector<int> batch_u(batch_edges.size()), batch_v(batch_edges.size());
		for (std::size_t i = 0; i < batch_edges.size(); ++i) {
			batch_u[i] = static_cast<int>(batch_edges[i] >> 32);
			batch_v[i] = static_cast<int>(batch_edges[i] & 0xFFFFFFFFu);
		}

		const auto batch_start = std::chrono::steady_clock::now();

		CUDA_CHECK(cudaMemcpy(g_bcc_ds.original_u + numEdges, batch_u.data(),
					batch_u.size() * sizeof(int), cudaMemcpyHostToDevice),
					"Unable to copy batch_u array to device");
		CUDA_CHECK(cudaMemcpy(g_bcc_ds.original_v + numEdges, batch_v.data(),
					batch_v.size() * sizeof(int), cudaMemcpyHostToDevice),
					"Unable to copy batch_v array to device");

		// Cut-vertex status must be recomputed from scratch each round,
		// since previously unsafe components can become safe.
		CUDA_CHECK(cudaMemset(g_bcc_ds.d_cut_vertex, 0, numVert * sizeof(int)),
					"Failed to reset d_cut_vertex before batch update");

		lca_batch(g_bcc_ds, numEdges, static_cast<long>(batch_u.size()));
		assign_cut_vertex_BCC(g_bcc_ds, g_bcc_ds.root, g_bcc_ds.child_of_root);

		const auto batch_end = std::chrono::steady_clock::now();
		std::cout << "Batch processing time: "
				  << std::chrono::duration<double, std::milli>(batch_end - batch_start).count()
				  << " ms\n";
	}

	if(write_output) {
		std::vector<int> host_cut_vertex(numVert);
		CUDA_CHECK(cudaMemcpy(host_cut_vertex.data(), g_bcc_ds.d_cut_vertex, numVert * sizeof(int), cudaMemcpyDeviceToHost), 
					"Failed to copy d_cut_vertex to host");

		std::vector<int> host_implicit_bcc_number(numVert);
		CUDA_CHECK(cudaMemcpy(host_implicit_bcc_number.data(), g_bcc_ds.d_imp_bcc_num, numVert * sizeof(int), cudaMemcpyDeviceToHost), 
					"Failed to copy d_imp_bcc_num to host");

		filename = get_file_extension(filename);
		filename += "_result.txt";
		filename = output_path + filename;

		std::cout << "Writing output to: " << filename << std::endl;
		
		std::ofstream outfile(filename);
   		if(!outfile) {
   			std::cerr <<"Unable to create file.\n";
   			return EXIT_FAILURE;
   		}
   		outfile << numVert << std::endl; //<<"\t" << numEdges << std::endl;
   		int ncv, j; //ncv -> num_Cut_vertex
   		j = ncv = 0;
   		outfile << "cut vertex status\n";
   		for(const auto&i : host_cut_vertex) {
   			if(i)
   	        	ncv++;
   			outfile << j++ << "\t" << i << std::endl;
   		}
   		std::cout <<"Total CV count: " << ncv << std::endl;
   
   		j = 0;
   		outfile << "vertex BCC number\n";
   		for(const auto&i : host_implicit_bcc_number)
   			outfile << j++ << "\t" << i << std::endl;

   		// assign edge bcc numbers
   		std::vector<int> edge_bcc_num(numEdges);
   		int *d_parent = g_bcc_ds.d_parent;
   		std::vector<int> h_parent(numVert);

		CUDA_CHECK(cudaMemcpy(h_parent.data(), d_parent, numVert * sizeof(int), cudaMemcpyDeviceToHost), 
	    				"Failed to copy back parent array to host.");
   		assign_edge_bcc(G.u_arr, G.v_arr, edge_bcc_num, host_implicit_bcc_number, host_cut_vertex, h_parent);

   		// write edge_bcc numbers
		j = 0;
   		outfile << "edge BCC numbers\n";
   		outfile << numEdges << "\n";
   		for(long i = 0; i < numEdges; ++i) {
   			outfile << G.u_arr[i] <<" - " << G.v_arr[i] << " -> " << edge_bcc_num[i] << std::endl;
   		}

   		int nbcc = 0;
		std::unordered_set<int> seen_bcc;

		for(int i = 0; i < numEdges; ++i){
			if( seen_bcc.find(edge_bcc_num[i]) == seen_bcc.end() ){
				nbcc++;
				seen_bcc.insert(edge_bcc_num[i]);
			}
		}

		outfile << ncv << " " << nbcc << "\n";
   	}
    return EXIT_SUCCESS;
}