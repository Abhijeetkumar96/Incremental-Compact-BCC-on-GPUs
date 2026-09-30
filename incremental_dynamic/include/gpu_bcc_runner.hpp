#ifndef GPU_BCC_RUNNER_HPP
#define GPU_BCC_RUNNER_HPP

// Plain C++ interface (no CUDA headers) so host-only code can call the GPU path.

#include <cstdint>
#include <string>
#include <vector>

#include "graph_input.hpp"

struct GpuBccOptions {
    bool write_output = false;
    std::string output_directory = "output/";
};

struct GpuBccResult {
    double batch_ms = 0.0;
    long num_cut_vertices = 0;
};

// Runs static BCC on `graph`, then inserts `batch` (packed u < v edges not in
// the graph) and updates cut vertices. Only the batch phase is timed.
GpuBccResult run_gpu_bcc(const GraphInput& graph,
                         const std::vector<std::uint64_t>& batch,
                         const GpuBccOptions& options);

#endif // GPU_BCC_RUNNER_HPP
