#ifndef HRBK22_HPP
#define HRBK22_HPP

#include <cstdint>
#include <vector>

#include "graph_input.hpp"

struct Hrbk22Result {
    double batch_ms = 0.0;
    long num_cut_vertices = 0;
};

// Builds the static state for `graph`, then inserts `batch` (packed u < v edges
// not in the graph) and recomputes cut vertices. Only the batch phase is timed.
Hrbk22Result run_hrbk22(const GraphInput& graph,
                        const std::vector<std::uint64_t>& batch);

#endif // HRBK22_HPP
