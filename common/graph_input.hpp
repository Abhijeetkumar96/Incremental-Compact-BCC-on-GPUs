#ifndef COMMON_GRAPH_INPUT_HPP
#define COMMON_GRAPH_INPUT_HPP

// Shared graph reader and batch generator. The graph is read from disk once
// and the same in-memory copy (plus the same batch) is handed to every
// implementation, so all codes see identical input.

#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

inline std::uint64_t pack_edge(int u, int v)
{
    return (static_cast<std::uint64_t>(static_cast<std::uint32_t>(u)) << 32) |
           static_cast<std::uint32_t>(v);
}

inline int edge_u(std::uint64_t edge) { return static_cast<int>(edge >> 32); }

inline int edge_v(std::uint64_t edge)
{
    return static_cast<int>(static_cast<std::uint32_t>(edge));
}

struct GraphInput {
    std::string path;
    int numVert = 0;

    // CSR: offsets has numVert + 1 entries, neighbors has 2|E| entries.
    std::vector<long> offsets;
    std::vector<int> neighbors;

    // Each undirected edge once, packed with u < v.
    std::vector<std::uint64_t> edges;

    long numEdges() const { return static_cast<long>(edges.size()); }
};

namespace graph_input_detail {

inline void csr_to_edges(GraphInput& g)
{
    const long m2 = static_cast<long>(g.neighbors.size());

    if (g.offsets.front() != 0 || g.offsets.back() != m2)
        throw std::runtime_error("Corrupt CSR offsets in: " + g.path);

    g.edges.reserve(m2 / 2);

    for (long u = 0; u < g.numVert; ++u) {
        if (g.offsets[u] > g.offsets[u + 1])
            throw std::runtime_error("Non monotonic CSR offsets in: " + g.path);

        for (long j = g.offsets[u]; j < g.offsets[u + 1]; ++j) {
            const int v = g.neighbors[j];
            if (v < 0 || v >= g.numVert)
                throw std::runtime_error("Vertex id out of range in: " + g.path);
            if (u < v)
                g.edges.push_back(pack_edge(static_cast<int>(u), v));
        }
    }
}

inline void edges_to_csr(GraphInput& g)
{
    g.offsets.assign(g.numVert + 1, 0);

    for (std::uint64_t e : g.edges) {
        ++g.offsets[edge_u(e) + 1];
        ++g.offsets[edge_v(e) + 1];
    }
    for (long i = 0; i < g.numVert; ++i)
        g.offsets[i + 1] += g.offsets[i];

    g.neighbors.resize(2 * g.edges.size());
    std::vector<long> cursor(g.offsets.begin(), g.offsets.end() - 1);

    for (std::uint64_t e : g.edges) {
        const int u = edge_u(e);
        const int v = edge_v(e);
        g.neighbors[cursor[u]++] = v;
        g.neighbors[cursor[v]++] = u;
    }
}

// Text format: "numVert numDirectedEdges" followed by "u v" lines, with
// both (u,v) and (v,u) present.
inline void read_edge_list(GraphInput& g)
{
    std::ifstream in(g.path);
    if (!in)
        throw std::runtime_error("Error opening file: " + g.path);

    long m = 0;
    if (!(in >> g.numVert >> m) || g.numVert < 0 || m < 0)
        throw std::runtime_error("Invalid edge list header in: " + g.path);

    g.edges.reserve(m / 2);

    int u, v;
    for (long i = 0; i < m; ++i) {
        if (!(in >> u >> v))
            throw std::runtime_error("Truncated edge list in: " + g.path);
        if (u < 0 || v < 0 || u >= g.numVert || v >= g.numVert)
            throw std::runtime_error("Vertex id out of range in: " + g.path);
        if (u < v)
            g.edges.push_back(pack_edge(u, v));
    }

    edges_to_csr(g);
}

// ECL binary CSR: size_t #offsets, size_t #neighbors, long offsets[], int neighbors[].
inline void read_ecl_graph(GraphInput& g)
{
    std::ifstream in(g.path, std::ios::binary);
    if (!in)
        throw std::runtime_error("Error opening file: " + g.path);

    std::size_t num_offsets = 0, num_entries = 0;
    if (!in.read(reinterpret_cast<char*>(&num_offsets), sizeof(num_offsets)) ||
        !in.read(reinterpret_cast<char*>(&num_entries), sizeof(num_entries)))
        throw std::runtime_error("Truncated CSR header in: " + g.path);

    // Reject sizes the file cannot hold before allocating.
    const std::uintmax_t file_size = std::filesystem::file_size(g.path);
    const std::uintmax_t payload =
        file_size >= 2 * sizeof(std::size_t) ? file_size - 2 * sizeof(std::size_t) : 0;

    if (num_offsets < 1 || num_offsets > payload / sizeof(long) ||
        num_entries > (payload - num_offsets * sizeof(long)) / sizeof(int))
        throw std::runtime_error("Corrupt CSR sizes in: " + g.path);

    g.offsets.resize(num_offsets);
    g.neighbors.resize(num_entries);

    if (!in.read(reinterpret_cast<char*>(g.offsets.data()), num_offsets * sizeof(long)) ||
        !in.read(reinterpret_cast<char*>(g.neighbors.data()), num_entries * sizeof(int)))
        throw std::runtime_error("Truncated CSR payload in: " + g.path);

    g.numVert = static_cast<int>(num_offsets - 1);
    csr_to_edges(g);
}

} // namespace graph_input_detail

inline GraphInput read_graph(const std::string& path)
{
    if (!std::filesystem::exists(path))
        throw std::runtime_error("File does not exist: " + path);

    GraphInput g;
    g.path = path;

    const std::string ext = std::filesystem::path(path).extension().string();

    if (ext == ".edges" || ext == ".eg2" || ext == ".txt")
        graph_input_detail::read_edge_list(g);
    else if (ext == ".egr" || ext == ".bin" || ext == ".csr")
        graph_input_detail::read_ecl_graph(g);
    else
        throw std::runtime_error("Unsupported graph format: " + ext);

    return g;
}

// Up to k random edges (u < v) not already in the graph, sorted and distinct.
// Deterministic for a given (graph, k, seed).
inline std::vector<std::uint64_t> generate_batch(
    const GraphInput& g, int k, std::uint64_t seed = 12345)
{
    if (k <= 0 || g.numVert < 2)
        return {};

    // CSR with sorted adjacency already yields a sorted edge list; avoid the copy then.
    std::vector<std::uint64_t> sorted_copy;
    const std::vector<std::uint64_t>* sorted = &g.edges;
    if (!std::is_sorted(g.edges.begin(), g.edges.end())) {
        sorted_copy = g.edges;
        std::sort(sorted_copy.begin(), sorted_copy.end());
        sorted = &sorted_copy;
    }

    auto edge_exists = [&](std::uint64_t e) {
        return std::binary_search(sorted->begin(), sorted->end(), e);
    };

    std::mt19937_64 gen(seed);
    std::uniform_int_distribution<int> dis(0, g.numVert - 1);
    constexpr int max_attempts = 100;

    std::vector<std::uint64_t> batch;
    batch.reserve(k);

    for (int i = 0; i < k; ++i) {
        for (int attempt = 0; attempt < max_attempts; ++attempt) {
            int u = dis(gen);
            int v = dis(gen);
            if (u == v)
                continue;
            if (u > v)
                std::swap(u, v);

            const std::uint64_t e = pack_edge(u, v);
            if (!edge_exists(e)) {
                batch.push_back(e);
                break;
            }
        }
    }

    std::sort(batch.begin(), batch.end());
    batch.erase(std::unique(batch.begin(), batch.end()), batch.end());
    return batch;
}

#endif // COMMON_GRAPH_INPUT_HPP
