#include "hrbk22.hpp"

#include "spanning_tree.hxx"
#include "lca.hxx"
#include "cc.hpp"

#include "parlay/sequence.h"
#include "parlay/parallel.h"
#include "parlay/primitives.h"

#include <iostream>
#include <vector>
#include <utility>
#include <cstdlib>
#include <climits>
#include <chrono>
#include <stdexcept>

// ============================================================
// Global state
// ============================================================

std::vector<int> in_fundamental_cycle;
std::vector<int> is_base_vertex;
std::vector<int> is_safe;
std::vector<int> is_lca;

std::vector<uint64_t> edge_base_vertices;


// ============================================================
// Fundamental cycle state
// ============================================================

static void build_fundamental_cycle_state(
    const std::vector<uint64_t>& edges,
    const std::vector<int>& parent,
    const std::vector<int>& depth)
{
    if (parent.size() != depth.size()) {
        throw std::invalid_argument(
            "parent and depth sizes do not match");
    }

    in_fundamental_cycle.assign(parent.size(), false);
    is_safe.assign(parent.size(), false);
    is_lca.assign(parent.size(), false);
    is_base_vertex.assign(parent.size(), false);
    edge_base_vertices.assign(edges.size(), UINT64_MAX);

    // --------------------------------------------------------
    // Process non-tree edges
    // --------------------------------------------------------
    parlay::parallel_for(0, edges.size(), [&](std::size_t edge_id) {
        const int u = edge_u(edges[edge_id]);
        const int v = edge_v(edges[edge_id]);

        // Tree edge -- skip
        if (parent[u] == v || parent[v] == u)
            return;

        lca(
            u,
            v,
            static_cast<int>(edge_id),
            parent,
            depth);
    });
}

#ifdef DEBUG
static void print_info(
    const std::vector<int>& parent,
    const std::vector<uint64_t>& edges)
{
    std::cout << "\nLCA vertices:\n";

    for (int i = 0; i < static_cast<int>(parent.size()); ++i) {

        if (is_lca[i])
            std::cout
                << "vertex "
                << i
                << " is an LCA\n";
    }

    // --------------------------------------------------------
    // Identify bridges
    // --------------------------------------------------------

    std::cout << "\nBridge status:\n";

    for (const auto& edge : edges) {

        const int u = edge_u(edge);
        const int v = edge_v(edge);

        int child = -1;

        if (parent[u] == v) {
            child = u;
        }
        else if (parent[v] == u) {
            child = v;
        }
        else {
            continue;
        }
        if (!in_fundamental_cycle[child]) {

            std::cout
                << "Tree edge ("
                << parent[child]
                << ", "
                << child
                << ") is a bridge\n";
        }
    }

    // --------------------------------------------------------
    // Print safe vertices
    // --------------------------------------------------------

    std::cout << "\nSafe vertices:\n";

    for (int i = 0; i < static_cast<int>(parent.size()); ++i) {

        if (is_safe[i])
            std::cout
                << "vertex "
                << i
                << " is safe\n";
    }

    // --------------------------------------------------------
    // Print per-edge base vertices
    // --------------------------------------------------------

    std::cout << "\nPer-edge base vertices:\n";

    for (std::size_t edge_id = 0;
         edge_id < edges.size();
         ++edge_id) {

        std::cout
            << "edge " << edge_id
            << " (" << edge_u(edges[edge_id])
            << ", " << edge_v(edges[edge_id])
            << "): base vertices = ("
            << (edge_base_vertices[edge_id] >> 32)
            << ", "
            << (edge_base_vertices[edge_id] & 0xFFFFFFFF)
            << ")\n";
    }

}
#endif

// ============================================================
// Entry point
// ============================================================

Hrbk22Result run_hrbk22(
    const GraphInput& graph,
    const std::vector<uint64_t>& B)
{
    const int n = graph.numVert;
    const auto& graph_edges = graph.edges;

    if (n <= 0)
        throw std::invalid_argument("graph has no vertices");

    // --------------------------------------------------------
    // Construct rooted spanning tree
    // --------------------------------------------------------

    int root = rand() % n;

    std::vector<int> parent;
    std::vector<int> depth;

    build_rooted_spanning_tree(
        graph,
        root,
        parent,
        depth);

#ifdef DEBUG
    std::cout << "Rooted spanning tree:\n";

    int i = 0;

    for (auto p : parent)
        std::cout
            << "parent[" << i++ << "] = "
            << p << "\n";
#endif

    // --------------------------------------------------------
    // Build fundamental cycle state
    // --------------------------------------------------------

    build_fundamental_cycle_state(
        graph_edges,
        parent,
        depth);

#ifdef DEBUG
    std::cout << "\nBatch size: " << B.size() << "\n";

    std::cout << "\nNewly added edges:\n";

    for (std::size_t i = 0; i < B.size(); ++i) {
        std::cout
            << "  batch edge " << i
            << " (id " << graph_edges.size() + i << "): ("
            << edge_u(B[i])
            << ", "
            << edge_v(B[i])
            << ")\n";
    }

    std::cout << "\n\nProcessing batch B:\n\n";
#endif

    // Batch ids continue past the graph edges so they do not overwrite them.
    const std::size_t batch_id_base = graph_edges.size();

    edge_base_vertices.resize(
        batch_id_base + B.size(), UINT64_MAX);
    // --------------------------------------------------------
    // Process batch
    // --------------------------------------------------------

    const auto batch_start = std::chrono::steady_clock::now();

    parlay::parallel_for(0, B.size(), [&](std::size_t i) {
        lca(
            edge_u(B[i]),
            edge_v(B[i]),
            static_cast<int>(batch_id_base + i),
            parent,
            depth);
    });

#ifdef DEBUG
    std::cout << "\nFinished processing batch.\n";
    std::cout << "Fundamental cycle state:\n";
    for(auto in_cycle : in_fundamental_cycle)
        std::cout << in_cycle << " ";
    std::cout << "\n";

    print_info(parent, graph_edges);

    std::cout << "NumVert: " << n << " and numEdges: "
              << graph_edges.size() << std::endl;
#endif

    // call cc on the base vertices
    parlay::sequence<uint64_t> edges =
        parlay::sequence<uint64_t>::from_function(
            edge_base_vertices.size(),
            [&](std::size_t edge_id) {
                return edge_base_vertices[edge_id];
            });
    parlay::sequence<int> label = parlay::sequence<int>::from_function(n, [](size_t i) { return static_cast<int>(i); });
    parlay::sequence<int> temp_label = parlay::sequence<int>::from_function(n, [](size_t i) { return static_cast<int>(i); });
    parlay::sequence<uint64_t> sptree = parlay::sequence<uint64_t>::from_function(n, [](size_t) { return static_cast<uint64_t>(INT_MAX); });

    [[maybe_unused]] const long num_components =
        connect_it(
            n,
            static_cast<long>(edges.size()),
            edges,
            label,
            temp_label,
            sptree);

#ifdef DEBUG
    std::cout << "Connected components: "
              << num_components << "\n";
    std::cout << "Component labels:\n";
    for (int component_label : label)
        std::cout << component_label << " ";
    std::cout << "\n";
#endif

    // ========================================================
    // Cut-vertex computation
    // ========================================================

    // --------------------------------------------------------
    // Identify base vertices
    // --------------------------------------------------------

    parlay::parallel_for(0, edge_base_vertices.size(),
        [&](std::size_t edge_id) {

        uint64_t base = edge_base_vertices[edge_id];

        if (base == UINT64_MAX)
            return;

        int u = static_cast<int>(base >> 32);
        int v = static_cast<int>(base & 0xFFFFFFFF);

        if (u >= 0 && u < n)
            is_base_vertex[u] = true;

        if (v >= 0 && v < n)
            is_base_vertex[v] = true;
    });

    // --------------------------------------------------------
    // Propagate safeness from base vertices to representatives
    // --------------------------------------------------------

    // Monotone: entries only go 0 -> 1, so the result is order independent.
    parlay::parallel_for(0, n, [&](long v) {

        if (is_base_vertex[v] && is_safe[v]) {
            is_safe[label[v]] = true;
        }
    });

    // --------------------------------------------------------
    // Propagate safeness from representatives to vertices
    // --------------------------------------------------------

    parlay::parallel_for(0, n, [&](long v) {

        if (is_safe[label[v]]) {
            is_safe[v] = true;
        }
    });

    // --------------------------------------------------------
    // Find unsafe components
    // --------------------------------------------------------

    std::vector<int> is_cut_vertex(n, false);

    int total_child = 0;

    for (int v = 0; v < n; ++v) {

        // Only representatives
        if (label[v] != v)
            continue;

        // Root handled separately
        if (v == root)
            continue;

        // Unsafe component
        if (!is_safe[v]) {

            int p = parent[v];

            is_cut_vertex[p] = true;

            if (p == root) {
                is_cut_vertex[root] = false;
                ++total_child;
            }
        }
    }

    // --------------------------------------------------------
    // Root condition
    // --------------------------------------------------------

    if (total_child >= 2) {
        is_cut_vertex[root] = true;
    }

    // --------------------------------------------------------
    // Degree of every vertex
    // --------------------------------------------------------

    std::vector<int> degree(n, 0);

    // CSR offsets already encode degree, so no accumulation race.
    const std::vector<long>& degree_offsets = graph.offsets;

    parlay::parallel_for(0, n, [&](long v) {
        degree[v] = static_cast<int>(
            degree_offsets[v + 1] - degree_offsets[v]);
    });

    // --------------------------------------------------------
    // Bridge condition
    // --------------------------------------------------------

    parlay::parallel_for(0, n, [&](long u) {

        int v = parent[u];

        if (u == v)
            return;

        // Parent edge participates in a fundamental cycle,
        // therefore it is not a bridge.
        if (in_fundamental_cycle[u])
            return;

        // (c) incident to a cut edge
        // (d) degree >= 2

        if (degree[u] > 1)
            is_cut_vertex[u] = true;

        if (degree[v] > 1)
            is_cut_vertex[v] = true;
    });

    const auto batch_end = std::chrono::steady_clock::now();

    Hrbk22Result result;
    result.batch_ms =
        std::chrono::duration<double, std::milli>(batch_end - batch_start).count();

    for (int v = 0; v < n; ++v)
        result.num_cut_vertices += is_cut_vertex[v] ? 1 : 0;

#ifdef DEBUG
    std::cout << "\nCut vertices:\n";

    for (int v = 0; v < n; ++v) {

        if (is_cut_vertex[v]) {
            std::cout
                << "vertex "
                << v
                << " is a cut vertex\n";
        }
    }
#endif

    return result;
}
