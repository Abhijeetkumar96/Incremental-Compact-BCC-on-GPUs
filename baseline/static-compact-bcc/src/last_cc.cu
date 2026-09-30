#include <vector>
#include <chrono>
#include <iostream>
#include <cuda_runtime.h>

#include "last_cc.cuh"
#include "cuda_utility.cuh"
#include "bcc_memory_utils.cuh"

// #define DEBUG

__global__
void _initialise(int* parent, int n) {
    int tid = blockDim.x * blockIdx.x + threadIdx.x;
    if(tid < n) {
        parent[tid] = tid;
    }
}

__global__ 
void _short_cutting(int n, int* d_parent) {
    int tid = blockDim.x * blockIdx.x + threadIdx.x;
    if(tid < n) {
        if(d_parent[tid] != tid) {
            d_parent[tid] = d_parent[d_parent[tid]];
        }
    }   
}

// Device function: can be called from kernels
__device__ inline void hook_union(
    int comp_u,
    int comp_v,
    int *d_rep,
    int *d_flag,
    int itr_no)
{
    if (comp_u == comp_v) return;

    // mark that something changed
    *d_flag = 1;   // or atomicExch(d_flag, 1);

    int mx  = (comp_u > comp_v) ? comp_u : comp_v;
    int mn  = (comp_u < comp_v) ? comp_u : comp_v;

    if (itr_no & 1) {
        d_rep[mn] = mx;
    } else {
        d_rep[mx] = mn;
    }
}

__global__
void identify_bridges_kernel(
        int numVert,
        int total_vertices,
        int numEdges,
        const int *d_source,
        const int *d_destination,
        const long *d_offset,
        int *d_rep,
        int *d_flag,
        int* d_cut_vertex, 
        int itr_no,
        const int *d_old_parent,
        const int *d_parent,
        const int *d_isSafe,
        const int *d_isPartOfFund) {

    int tid = blockIdx.x * blockDim.x + threadIdx.x;

    if (tid == 0) {
        printf("---- d_offset array (size = %d) ----\n", total_vertices + 1);
        for (int x = 0; x <= total_vertices; x++) {
            printf("offset[%d] = %ld\n", x, d_offset[x]);
        }
        printf("------------------------------------\n");
    }


    // ------------------------------------------------------
    // PART 1: Process all non-tree edges (source–destination)
    // ------------------------------------------------------
    if (tid < numEdges) {

        int u = d_source[tid];
        int v = d_destination[tid];

        // skip tree edges
        if (d_old_parent[u] == v || d_old_parent[v] == u)
            ;  // do nothing
        else {
            int comp_u = d_rep[u];
            int comp_v = d_rep[v];
            // printf("Calling hook_union for u: %d, v:%d\n", u, v);
            hook_union(comp_u, comp_v, d_rep, d_flag, itr_no);
        }
    }

    // ------------------------------------------------------
    // PART 2: Process parent edges (tree edges i → parent[i])
    // ------------------------------------------------------
    if (tid < total_vertices) {

        int i   = tid;
        int par = d_parent[i];

        // invalid parent → skip
        if (par < 0 || par >= total_vertices || par == i)
            return;

        // CASE 1: Alias vertex
        if (i >= numVert) {
            if (d_isPartOfFund[i] == 0) {    
                printf("BRIDGE (alias): %d -- %d\n\n", i, par);
                d_cut_vertex[par] = 1;
                // printf("%d is UNSAFE, par is %d and cutVertex[par]: %d\n",i, par, d_cut_vertex[par]);
                return;   // not safe → treat as bridge, no hook
            }
        }

        // CASE 2: Original vertex
        else {

            if (d_isPartOfFund[i] == 0) {
                printf("BRIDGE (original): %d -- %d\n", i, par);

                int u = i;
                int v = par;

                if (d_offset[u+1] - d_offset[u] > 1) {
                    printf("  marking %d as CUT VERTEX (deg=%ld)\n", 
                            u, d_offset[u+1] - d_offset[u]);
                    d_cut_vertex[u] = 1;
                }

                if (d_offset[v+1] - d_offset[v] > 1) {
                    printf("  marking %d as CUT VERTEX (deg=%ld)\n", 
                            v, d_offset[v+1] - d_offset[v]);
                    d_cut_vertex[v] = 1;
                }

                return;   // not part of fund → bridge, no hook
            }
        }

        // If we reach here, (i, par) is considered "non-bridge" and
        // can be used in hooking / union.
        int comp_u = d_rep[i];
        int comp_v = d_rep[par];
        // printf("Calling hook_union for i: %d, par[i]:%d\n", i, par);
        hook_union(comp_u, comp_v, d_rep, d_flag, itr_no);
    }
}

__global__
void debug_cut_kernel(
    int numVert,
    int total_vertices,
    const int *d_old_parent,
    const int *d_parent,
    const int *d_isSafe,
    const int *d_isPartOfFund,
    const int *d_rep,
    const int *d_cut_vertex) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= total_vertices) return;

    int i        = tid;
    int old_par  = d_old_parent ? d_old_parent[i] : -1;
    int par      = d_parent     ? d_parent[i]     : -1;
    int isSafe   = d_isSafe     ? d_isSafe[i]     : -1;
    int inFund   = d_isPartOfFund ? d_isPartOfFund[i] : -1;
    int rep      = d_rep        ? d_rep[i]        : -1;
    int cut      = d_cut_vertex ? d_cut_vertex[i] : -1;

    printf(
        "DBG i=%2d | old_par=%2d par=%2d | isSafe=%2d inFund=%2d | rep=%2d | cut=%2d%s\n",
        i, old_par, par, isSafe, inFund, rep, cut,
        (i >= numVert ? " (alias)" : " (orig)")
    );
}


void last_cc(gpu_bcc& g_bcc_ds) {

    int  numVert         = g_bcc_ds.numVert;
    int  total_vertices  = g_bcc_ds.total_vertices;   
    int  numEdges        = g_bcc_ds.numEdges;

    int *d_rep           = g_bcc_ds.d_rep;
    int *u_arr           = g_bcc_ds.original_u;
    int *v_arr           = g_bcc_ds.original_v;
    int *d_flag          = g_bcc_ds.d_flag;          
    int *d_old_parent    = g_bcc_ds.d_level;
    int *d_parent        = g_bcc_ds.d_parent;
    int *d_isSafe        = g_bcc_ds.d_isSafe;
    int *d_cut_vertex    = g_bcc_ds.d_cut_vertex;
    int *d_isPartofFund  = g_bcc_ds.d_isPartofFund;
    long *d_offset       =  g_bcc_ds.d_vertices;

    const int numThreads = 1024;

    // for _initialise and shortcutting
    int numBlocks_vert   = (total_vertices + numThreads - 1) / numThreads;
    // for combined kernel: need to cover both edges and vertices
    int span             = max(numEdges, total_vertices);
    int numBlocks_comb   = (span + numThreads - 1) / numThreads;

    // 1. init reps: rep[i] = i
    _initialise<<<numBlocks_vert, numThreads>>>(d_rep, total_vertices);
    cudaError_t err = cudaGetLastError();
    CUDA_CHECK(err, "Error in launching _initialise kernel");

    int flag = 1;
    int iteration = 0;

    while (flag) {
        flag = 0;
        iteration++;

        CUDA_CHECK(
            cudaMemcpy(d_flag, &flag, sizeof(int),
                       cudaMemcpyHostToDevice),
            "Unable to copy the flag to device"
        );

        // 2. One hooking round using identify_bridges_kernel
        identify_bridges_kernel<<<numBlocks_comb, numThreads>>>(
            numVert,
            total_vertices,
            numEdges,
            u_arr,
            v_arr,
            d_offset,
            d_rep,
            d_flag,
            d_cut_vertex,
            iteration,
            d_old_parent,
            d_parent,
            d_isSafe,
            d_isPartofFund
        );

        err = cudaGetLastError();
        CUDA_CHECK(err, "Error in launching identify_bridges_kernel");

        // 3. Shortcutting: O(log n) pointer jumping
        int rounds = (int)std::ceil(std::log2((double)total_vertices));
        for (int i = 0; i < rounds; ++i) {
            _short_cutting<<<numBlocks_vert, numThreads>>>(
                total_vertices, d_rep
            );
            err = cudaGetLastError();
            CUDA_CHECK(err, "Error in launching _short_cutting kernel");
        }

        CUDA_CHECK(
            cudaMemcpy(&flag, d_flag, sizeof(int),
                       cudaMemcpyDeviceToHost),
            "Unable to copy back flag to host"
        );
    }

    int dbgThreads = 128;
    int dbgBlocks  = (total_vertices + dbgThreads - 1) / dbgThreads;

    #ifdef DEBUG

        printf("\n\n============ DEVICE DEBUG DUMP ============\n");
        debug_cut_kernel<<<dbgBlocks, dbgThreads>>>(
            numVert,
            total_vertices,
            d_old_parent,
            d_parent,
            d_isSafe,
            d_isPartofFund,
            d_rep,
            d_cut_vertex
        );
        cudaDeviceSynchronize();
        printf("============ END DEVICE DEBUG DUMP ==========\n\n");

        int n = total_vertices;
        std::vector<int> h_rep(n);
        std::vector<int> h_cut(n);

        CUDA_CHECK(
            cudaMemcpy(h_rep.data(), d_rep, n * sizeof(int), cudaMemcpyDeviceToHost),
            "cudaMemcpy failed while copying d_rep → h_rep (component representatives)"
        );

        CUDA_CHECK(
            cudaMemcpy(h_cut.data(), d_cut_vertex, numVert * sizeof(int), cudaMemcpyDeviceToHost),
            "cudaMemcpy failed while copying d_cut_vertex → h_cut (cut-vertex flags)"
        );

        CUDA_CHECK(cudaDeviceSynchronize(), "Failed to synchronize");

        std::cout << "\n===== d_rep (Component Representatives) =====\n";
        for (int i = 0; i < n; i++) {
            std::cout << "Vertex " << i << "  ->  Rep " << h_rep[i] << "\n";
        }
        std::cout << "============================================\n\n";

        std::cout << "===== Cut Vertex Flags (d_cut_vertex) =====\n";
        for (int i = 0; i < numVert; i++) {
            std::cout << "Vertex " << i << "  ->  Cut? " << h_cut[i] << "\n";
        }
        std::cout << "============================================\n\n";
    #endif

}
