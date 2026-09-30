// This version assigns correct edge labels to all bcc's

#include <string>
#include <vector>
#include <fstream>
#include <iostream>
#include <unordered_set>
#include <cstdint>
#include <chrono>

#include <cuda_runtime.h>

#include "gpu_bcc_runner.hpp"
#include "utility.hpp"

#include "bcc.cuh"
#include "lca.cuh"
#include "cut_vertex.cuh"
#include "cuda_utility.cuh"
#include "bcc_memory_utils.cuh"

static void assign_edge_bcc(const std::vector<int>& U, const std::vector<int>& V, std::vector<int>& edge_bcc_num, const std::vector<int>& imp_bcc_num, const std::vector<int>& cut_vertex, const std::vector<int>& parent) {
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

static void write_result(const gpu_bcc& g_bcc_ds, const std::vector<int>& U, const std::vector<int>& V,
						 const std::vector<int>& host_cut_vertex, const std::string& graph_path,
						 const std::string& output_path) {
	const int numVert = g_bcc_ds.numVert;
	const long numEdges = static_cast<long>(U.size());

	std::vector<int> host_implicit_bcc_number(numVert);
	CUDA_CHECK(cudaMemcpy(host_implicit_bcc_number.data(), g_bcc_ds.d_imp_bcc_num, numVert * sizeof(int), cudaMemcpyDeviceToHost),
				"Failed to copy d_imp_bcc_num to host");

	std::string filename = output_path + get_file_extension(graph_path) + "_result.txt";

	std::cout << "Writing output to: " << filename << std::endl;

	std::ofstream outfile(filename);
	if(!outfile) {
		std::cerr <<"Unable to create file.\n";
		return;
	}
	outfile << numVert << std::endl;
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
	std::vector<int> h_parent(numVert);

	CUDA_CHECK(cudaMemcpy(h_parent.data(), g_bcc_ds.d_parent, numVert * sizeof(int), cudaMemcpyDeviceToHost),
				"Failed to copy back parent array to host.");
	assign_edge_bcc(U, V, edge_bcc_num, host_implicit_bcc_number, host_cut_vertex, h_parent);

	// write edge_bcc numbers
	outfile << "edge BCC numbers\n";
	outfile << numEdges << "\n";
	for(long i = 0; i < numEdges; ++i) {
		outfile << U[i] <<" - " << V[i] << " -> " << edge_bcc_num[i] << std::endl;
	}

	std::unordered_set<int> seen_bcc(edge_bcc_num.begin(), edge_bcc_num.end());
	outfile << ncv << " " << seen_bcc.size() << "\n";
}

GpuBccResult run_gpu_bcc(const GraphInput& graph,
						 const std::vector<std::uint64_t>& batch,
						 const GpuBccOptions& options) {
	// Device is chosen externally via CUDA_VISIBLE_DEVICES.
	cudaFree(0);

	const int numVert = graph.numVert;
	const long numEdges = graph.numEdges();
	const long batchSize = static_cast<long>(batch.size());

	// Graph + batch edges unpacked into one u/v pair, laid out as on the device.
	std::vector<int> u_arr(numEdges + batchSize), v_arr(numEdges + batchSize);
	for (long i = 0; i < numEdges; ++i) {
		u_arr[i] = edge_u(graph.edges[i]);
		v_arr[i] = edge_v(graph.edges[i]);
	}
	for (long i = 0; i < batchSize; ++i) {
		u_arr[numEdges + i] = edge_u(batch[i]);
		v_arr[numEdges + i] = edge_v(batch[i]);
	}

	gpu_bcc g_bcc_ds(numVert, numEdges, batchSize);
	// Copy the edge-list
	CUDA_CHECK(cudaMemcpy(g_bcc_ds.original_u, u_arr.data(), numEdges * sizeof(int), cudaMemcpyHostToDevice),
				"Unable to copy original_u array to device");
	CUDA_CHECK(cudaMemcpy(g_bcc_ds.original_v, v_arr.data(), numEdges * sizeof(int), cudaMemcpyHostToDevice),
				"Unable to copy original_v array to device");

	// Copy the csr graph
	CUDA_CHECK(cudaMemcpy(g_bcc_ds.d_vertices, graph.offsets.data(), graph.offsets.size() * sizeof(long), cudaMemcpyHostToDevice),
				"Unable to copy csr_edge_offset array to device");
	CUDA_CHECK(cudaMemcpy(g_bcc_ds.d_edges, graph.neighbors.data(), graph.neighbors.size() * sizeof(int), cudaMemcpyHostToDevice),
				"Unable to copy csr_neighbour array to device");

	// init data_structures
	g_bcc_ds.init(numVert, numEdges);

	// start cuda_bcc
	cuda_bcc(g_bcc_ds);

	// --------------------------------------------------------
	// Batch update: incrementally update the fundamental-cycle
	// state, connected components, and cut vertices, reusing the
	// spanning tree computed above.
	// --------------------------------------------------------

	GpuBccResult result;

	if (batchSize > 0) {
		const auto batch_start = std::chrono::steady_clock::now();

		CUDA_CHECK(cudaMemcpy(g_bcc_ds.original_u + numEdges, u_arr.data() + numEdges,
					batchSize * sizeof(int), cudaMemcpyHostToDevice),
					"Unable to copy batch_u array to device");
		CUDA_CHECK(cudaMemcpy(g_bcc_ds.original_v + numEdges, v_arr.data() + numEdges,
					batchSize * sizeof(int), cudaMemcpyHostToDevice),
					"Unable to copy batch_v array to device");

		// Cut-vertex status must be recomputed from scratch each round,
		// since previously unsafe components can become safe.
		CUDA_CHECK(cudaMemset(g_bcc_ds.d_cut_vertex, 0, numVert * sizeof(int)),
					"Failed to reset d_cut_vertex before batch update");

		lca_batch(g_bcc_ds, numEdges, batchSize);
		assign_cut_vertex_BCC(g_bcc_ds, g_bcc_ds.root, g_bcc_ds.child_of_root);

		CUDA_CHECK(cudaDeviceSynchronize(), "Batch update failed");
		const auto batch_end = std::chrono::steady_clock::now();
		result.batch_ms = std::chrono::duration<double, std::milli>(batch_end - batch_start).count();
	}

	std::vector<int> host_cut_vertex(numVert);
	CUDA_CHECK(cudaMemcpy(host_cut_vertex.data(), g_bcc_ds.d_cut_vertex, numVert * sizeof(int), cudaMemcpyDeviceToHost),
				"Failed to copy d_cut_vertex to host");
	for (int cv : host_cut_vertex)
		result.num_cut_vertices += cv ? 1 : 0;

	if (options.write_output) {
		u_arr.resize(numEdges);
		v_arr.resize(numEdges);
		write_result(g_bcc_ds, u_arr, v_arr, host_cut_vertex, graph.path, options.output_directory);
	}

	return result;
}
