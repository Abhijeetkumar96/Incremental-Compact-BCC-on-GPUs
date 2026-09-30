#include <vector>
#include <chrono>
#include <iostream>
#include <cub/cub.cuh>
#include <cuda_runtime.h>

#include "cuda_utility.cuh"
#include "alias_vertices.cuh"
#include "bcc_memory_utils.cuh"

// #define DEBUG

__global__ 
void identify_auxiliary_vertex_count(
        int numVert,
        const int *d_rep,
        const int *d_is_baseVertex,
        int *d_mark) {

    int v = blockIdx.x * blockDim.x + threadIdx.x;
    if (v >= numVert) return;

    // If v is a base vertex
    if (d_is_baseVertex[v]) {
        int r = d_rep[v];
        // Mark representative
        d_mark[r] = 1;
    }
}

__global__
void create_alias_vertices(
        int n,
        const int *d_rep,
        const int *d_is_baseVertex,
        const int *d_inclusive,
        int *d_parent, int *d_isPartofFund)
{
    int v = blockIdx.x * blockDim.x + threadIdx.x;
    if (v >= n) return;

    if (d_is_baseVertex[v]) {

        int old_parent   = d_parent[v];
        int rep          = d_rep[v];
        int alias_offset = d_inclusive[rep];  // inclusive scan gives index
        int alias_vertex = n + alias_offset - 1;  // new vertex id

        // update parent of v
        d_parent[v] = alias_vertex;

        // set parent of alias vertex
        d_parent[alias_vertex] = old_parent;

        if(d_isPartofFund[old_parent]) 
            d_isPartofFund[alias_vertex] = 1;
    }
}

void add_alias_vertices(gpu_bcc& g_bcc_ds) {
    // std::cout << " Printing from identify_auxilary_vertex_count" << std::endl;
    int numVert          =  g_bcc_ds.numVert;
    int *d_rep           =  g_bcc_ds.d_rep;
    int *d_is_baseVertex =  g_bcc_ds.d_is_baseVertex; // My parent is lca or not
    int* d_mark          =  g_bcc_ds.d_imp_bcc_num;
    int *d_parent        =  g_bcc_ds.d_parent;
    int *d_isPartofFund  =  g_bcc_ds.d_isPartofFund;

    int threads = 1024;
    int blocks  = (numVert + threads - 1) / threads;

    identify_auxiliary_vertex_count<<<blocks, threads>>>(
        numVert,
        d_rep,
        d_is_baseVertex,
        d_mark
    );
    cudaDeviceSynchronize();

    int* d_inclusive;
    cudaMalloc(&d_inclusive, numVert * sizeof(int));

    // -----------------------------
    // 3. CUB Exclusive Scan
    // -----------------------------
    void *d_temp_storage = nullptr;
    size_t temp_bytes = 0;

    // Query temp storage size
    cub::DeviceScan::InclusiveSum(d_temp_storage, temp_bytes, d_mark, d_inclusive, numVert);
    CUDA_CHECK(cudaMalloc(&d_temp_storage, temp_bytes), "Failed to allocate d_temp_storage");

    // Actual exclusive scan
    cub::DeviceScan::InclusiveSum(d_temp_storage, temp_bytes, d_mark, d_inclusive, numVert);

    // Free temp storage
    CUDA_CHECK(cudaFree(d_temp_storage), "Failed to free d_temp_storage");

    create_alias_vertices<<<blocks,threads>>>(
    numVert,
    d_rep,
    d_is_baseVertex,
    d_inclusive,
    d_parent,
    d_isPartofFund
);

CUDA_CHECK(cudaDeviceSynchronize(), "Kernel launch failed: create_alias_vertices");

int last = 0;
CUDA_CHECK(
    cudaMemcpy(&last,
               d_inclusive + (numVert - 1),
               sizeof(int),
               cudaMemcpyDeviceToHost),
    "Memcpy failed for d_inclusive[last]"
);

int alias_vertices = last;            // inclusive sum gives final count
int total_vertices = numVert + alias_vertices;

std::vector<int> h_parent(total_vertices);
CUDA_CHECK(
    cudaMemcpy(h_parent.data(),
               d_parent,
               total_vertices * sizeof(int),
               cudaMemcpyDeviceToHost),
    "Memcpy failed for d_parent"
);

std::cout << "Total vertices = " << total_vertices << "\n";
g_bcc_ds.total_vertices = total_vertices;

#ifdef DEBUG
    std::cout << "Parent array:\n";
    for (int i = 0; i < total_vertices; i++) {
        std::cout << i << " -> " << h_parent[i] << "\n";
    }

    // ---- print isSafe ----
    std::vector<int> h_isPartofFund(total_vertices);
    CUDA_CHECK(
        cudaMemcpy(h_isPartofFund.data(),
                   d_isPartofFund,
                   total_vertices * sizeof(int),
                   cudaMemcpyDeviceToHost),
        "Memcpy failed for d_isPartofFund (full)"
    );

    std::cout << "Part of Fundamental cycle array:\n";
    for (int i = 0; i < total_vertices; i++)
        std::cout << i << " : " << h_isPartofFund[i] << "\n";

    // ---- print bridges ----
    std::cout << "\nIdentified Bridges:\n";

    std::vector<int> h_isPartOfFund(numVert);
    CUDA_CHECK(
        cudaMemcpy(h_isPartOfFund.data(),
                   d_isPartofFund,
                   numVert * sizeof(int),
                   cudaMemcpyDeviceToHost),
        "Memcpy failed for d_isPartofFund (partial)"
    );

    // for (int i = 0; i < total_vertices; i++) {

    //     int par = h_parent[i];

    //     // skip root / invalid parent
    //     if (par < 0 || par >= total_vertices) continue;
    //     if (i == par) continue;

    //     // CASE 1: Alias vertex
    //     if (i >= numVert) {
    //         if (h_isPartofFund[i] == 0) { 
    //             std::cout << "BRIDGE (alias): " << i << " -- " << par << "\n";
    //         }
    //     }

    //     // CASE 2: Original vertex
    //     else {
    //         if (h_isPartOfFund[i] == 0) {
    //             std::cout << "BRIDGE (original): " << i << " -- " << par << "\n";
    //         }
    //     }
    // }
    
#endif
}
