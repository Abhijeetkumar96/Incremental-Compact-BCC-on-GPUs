// This version assigns correct edge labels to all bcc's

#include <string>
#include <vector>
#include <fstream>
#include <iostream>
#include<unordered_set>

#include <unistd.h>
#include <cuda_runtime.h>

#include "graph.hpp"
#include "timer.hpp"
#include "utility.hpp"

#include "bcc.cuh"
#include "cuda_utility.cuh"
#include "bcc_memory_utils.cuh"
#include "CommandLineParser.cuh"

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
	std::cout <<"Reading input and csr creation finished in: " << formatDuration(dur) << std::endl;
	t1.reset();

	cudaFree(0);
	int numVert = G.numVert;
	long numEdges = G.u_arr.size();

	gpu_bcc g_bcc_ds(numVert, numEdges);
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

    return EXIT_SUCCESS;
}