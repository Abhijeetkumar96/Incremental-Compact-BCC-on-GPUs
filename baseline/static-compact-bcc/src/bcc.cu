#include <vector>
#include <string>
#include <random>
#include <chrono>
#include <cub/cub.cuh>
#include <cuda_runtime.h>

// Helper functions
#include "timer.hpp"
#include "utility.hpp"
#include "cuda_utility.cuh"

#include "bcc.cuh"
#include "bcc_memory_utils.cuh"

#include "bfs.cuh"

#include "lca.cuh"
#include "last_cc.cuh"
#include "alias_vertices.cuh"

// #define DEBUG

void cuda_bcc(gpu_bcc& g_bcc_ds) {

	long numEdges 	= g_bcc_ds.numEdges; // numEdges is unique edge count (only (2,1), not (1,2)).
	int numVert 	= g_bcc_ds.numVert;

	std::cout << "numEdges = " << numEdges << std::endl;
	std::cout << "numVert = " << numVert << std::endl;

	long E = 2 * numEdges; // Two times the original edges count (0,1) and (1,0).
    
    // csr data-structures
    long* d_vertices = g_bcc_ds.d_vertices;
    int* d_edges = g_bcc_ds.d_edges;

	int *d_parent = g_bcc_ds.d_parent;
	int *d_level = g_bcc_ds.d_level;

	// Create a random device and seed it
    std::random_device rd;
    std::mt19937 gen(rd());

    // Create a distribution in the range [0, numVert]
    std::uniform_int_distribution<> distrib(0, numVert - 1);

    // Generate a random root value
    int root = distrib(gen);
    root = 2;
    int root_level = 0;
    // Output the random root value
    std::cout << "Random root value: " << root << std::endl;

	int child_of_root = -1;

	auto start = std::chrono::high_resolution_clock::now();

	CUDA_CHECK(cudaMemcpy(&d_level[root], &root_level, sizeof(int), cudaMemcpyHostToDevice), "Failed to set root level.");
	constructSpanningTree(numVert, E, d_vertices, d_edges, d_level, d_parent, root, child_of_root);


	#ifdef DEBUG
		std::vector<int> h_parent(numVert);
		std::vector<int> h_level(numVert);
		CUDA_CHECK(cudaMemcpy(h_parent.data(), d_parent, numVert * sizeof(int), cudaMemcpyDeviceToHost), 
	    				"Failed to copy back parent array to host.");

		CUDA_CHECK(cudaMemcpy(h_level.data(), d_level, numVert * sizeof(int), cudaMemcpyDeviceToHost), 
	    				"Failed to copy back level array to host.");

		print(h_parent, "parent array");
		print(h_level,   "level array");
	#endif

	// Step 3 & 4 : Find LCA and Base Vertices, then apply connected Comp
    naive_lca(g_bcc_ds, root, child_of_root);
    // std::cout << "Calling add_alias_vertices function" << std::endl;
    add_alias_vertices(g_bcc_ds);
    last_cc(g_bcc_ds);

    auto end = std::chrono::high_resolution_clock::now();
    auto dur = std::chrono::duration_cast<std::chrono::milliseconds>(end - start).count();

	std::cout << "Time taken by WK-BCC: " << dur << " ms\n";
}
