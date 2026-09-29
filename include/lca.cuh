#ifndef LCA_H
#define LCA_H

#include <vector>
#include <string>
#include <iostream>
#include <cuda_runtime.h>

#include "bcc_memory_utils.cuh"

void naive_lca(gpu_bcc& g_bcc_ds, int root, int child_of_root);

// Runs LCA only over the batch edges appended at [batch_offset, batch_offset + batch_count)
// and recomputes connected components over the full base-vertex edge set, reusing the
// spanning tree and fundamental-cycle state already computed for the static graph.
void lca_batch(gpu_bcc& g_bcc_ds, long batch_offset, long batch_count);

#endif // LCA_H