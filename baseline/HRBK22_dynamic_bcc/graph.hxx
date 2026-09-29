#ifndef GRAPH_HXX
#define GRAPH_HXX

#include <filesystem>
#include <string>
#include <vector>
#include <utility>
#include <chrono>
#include <cstdint>

inline std::uint64_t pack_edge(int u, int v)
{
    return (static_cast<std::uint64_t>(
                static_cast<std::uint32_t>(u)) << 32) |
        static_cast<std::uint32_t>(v);
}

inline int edge_u(std::uint64_t edge)
{
    return static_cast<int>(edge >> 32);
}

inline int edge_v(std::uint64_t edge)
{
    return static_cast<int>(
        static_cast<std::uint32_t>(edge));
}

class undirected_graph {
private:
    std::filesystem::path filepath;

    // CSR adjacency, built for every input format.
    // vertices: numVert + 1 offsets, edges: 2|E| neighbour ids.
    std::vector<long> vertices;
    std::vector<int> edges;

    // Undirected edge list.
    // Only stores edges where u < v.
    std::vector<std::uint64_t> edgelist;

    int numVert = 0;
    long numEdges = 0;

    std::chrono::duration<double> read_duration;

    void readGraphFile();
    void readEdgeList();
    void readECLgraph();
    void csr_to_coo();
    void coo_to_csr();

public:
    undirected_graph(const std::string& filename);

    void print_edgelist() const;
    void basic_stats() const;

    inline int getNumVertices() const {
        return numVert;
    }

    inline long getNumEdges() const {
        return numEdges;
    }

    inline const std::vector<std::uint64_t>&
    getEdgelist() const {
        return edgelist;
    }

    // Neighbours of u are getNeighbors()[j]
    // for j in [getOffsets()[u], getOffsets()[u + 1]).
    inline const std::vector<long>& getOffsets() const {
        return vertices;
    }

    inline const std::vector<int>& getNeighbors() const {
        return edges;
    }
};

#include <iostream>
#include <fstream>
#include <queue>
#include <cassert>
#include <stdexcept>
#include <algorithm>


// ============================================================
// Constructor
// ============================================================

inline undirected_graph::undirected_graph(
    const std::string& filename)
    : filepath(filename)
{
    auto start =
        std::chrono::high_resolution_clock::now();

    readGraphFile();

    auto end =
        std::chrono::high_resolution_clock::now();

    read_duration = end - start;
}


// ============================================================
// Read graph according to file extension
// ============================================================

inline void undirected_graph::readGraphFile()
{
    if (!std::filesystem::exists(filepath)) {
        throw std::runtime_error(
            "File does not exist: " +
            filepath.string());
    }

    std::string ext =
        filepath.extension().string();

    if (ext == ".edges" ||
        ext == ".eg2" ||
        ext == ".txt") {

        readEdgeList();
    }
    else if (ext == ".egr" ||
             ext == ".bin" ||
             ext == ".csr") {

        readECLgraph();
    }
    else {
        throw std::runtime_error(
            "Unsupported graph format: " + ext);
    }
}


// ============================================================
// Read edge list
//
// First line:
//     numVert numEdges
//
// Remaining lines:
//     u v
//
// Since the graph is undirected, the input contains both
// (u,v) and (v,u). We retain only u < v.
// ============================================================

inline void undirected_graph::readEdgeList()
{
    std::ifstream inFile(filepath);

    if (!inFile) {
        throw std::runtime_error(
            "Error opening file: " +
            filepath.string());
    }

    if (!(inFile >> numVert >> numEdges) ||
        numVert < 0 ||
        numEdges < 0) {

        throw std::runtime_error(
            "Invalid edge list header in: " +
            filepath.string());
    }

    edgelist.reserve(numEdges / 2);

    int u, v;

    for (long i = 0; i < numEdges; ++i) {

        if (!(inFile >> u >> v)) {
            throw std::runtime_error(
                "Truncated edge list in: " +
                filepath.string());
        }

        if (u < 0 || v < 0 ||
            u >= numVert || v >= numVert) {

            throw std::runtime_error(
                "Vertex id out of range in: " +
                filepath.string());
        }

        if (u < v) {
            edgelist.push_back(pack_edge(u, v));
        }
    }

    assert(
        static_cast<long>(edgelist.size())
        == numEdges / 2
    );

    coo_to_csr();
}


// ============================================================
// Read ECLgraph / CSR
// ============================================================

inline void undirected_graph::readECLgraph()
{
    std::ifstream inFile(
        filepath,
        std::ios::binary);

    if (!inFile) {
        throw std::runtime_error(
            "Error opening file: " +
            filepath.string());
    }

    size_t num_offsets = 0;
    size_t num_entries = 0;

    if (!inFile.read(
            reinterpret_cast<char*>(&num_offsets),
            sizeof(num_offsets)) ||
        !inFile.read(
            reinterpret_cast<char*>(&num_entries),
            sizeof(num_entries))) {

        throw std::runtime_error(
            "Truncated CSR header in: " +
            filepath.string());
    }

    // Reject sizes the file cannot hold before allocating.
    const std::uintmax_t payload =
        std::filesystem::file_size(filepath)
        - 2 * sizeof(size_t);

    if (num_offsets < 1 ||
        num_offsets > payload / sizeof(long) ||
        num_entries >
            (payload - num_offsets * sizeof(long))
            / sizeof(int)) {

        throw std::runtime_error(
            "Corrupt CSR sizes in: " +
            filepath.string());
    }

    vertices.resize(num_offsets);
    edges.resize(num_entries);

    if (!inFile.read(
            reinterpret_cast<char*>(vertices.data()),
            vertices.size() * sizeof(long)) ||
        !inFile.read(
            reinterpret_cast<char*>(edges.data()),
            edges.size() * sizeof(int))) {

        throw std::runtime_error(
            "Truncated CSR payload in: " +
            filepath.string());
    }

    numVert = vertices.size() - 1;
    numEdges = edges.size();

    csr_to_coo();
}


// ============================================================
// Convert CSR to edge list
//
// Only retain u < v.
// ============================================================

inline void undirected_graph::csr_to_coo()
{
    if (vertices.front() != 0 ||
        vertices.back() != numEdges) {

        throw std::runtime_error(
            "Corrupt CSR offsets in: " +
            filepath.string());
    }

    edgelist.reserve(numEdges / 2);

    for (long u = 0; u < numVert; ++u) {

        if (vertices[u] > vertices[u + 1]) {
            throw std::runtime_error(
                "Non monotonic CSR offsets in: " +
                filepath.string());
        }

        for (long j = vertices[u];
             j < vertices[u + 1];
             ++j) {

            int v = edges[j];

            if (v < 0 || v >= numVert) {
                throw std::runtime_error(
                    "Vertex id out of range in: " +
                    filepath.string());
            }

            if (u < v) {
                edgelist.push_back(
                    pack_edge(static_cast<int>(u), v));
            }
        }
    }

    assert(
        static_cast<long>(edgelist.size())
        == numEdges / 2
    );
}


// ============================================================
// Build CSR from the edge list
//
// The edge list holds each undirected edge once (u < v), so
// every entry contributes a neighbour to both endpoints.
// ============================================================

inline void undirected_graph::coo_to_csr()
{
    vertices.assign(numVert + 1, 0);

    for (std::uint64_t edge : edgelist) {
        const int u = edge_u(edge);
        const int v = edge_v(edge);
        ++vertices[u + 1];
        ++vertices[v + 1];
    }

    for (long i = 0; i < numVert; ++i) {
        vertices[i + 1] += vertices[i];
    }

    edges.resize(2 * edgelist.size());

    std::vector<long> cursor(
        vertices.begin(),
        vertices.end() - 1);

    for (std::uint64_t edge : edgelist) {
        const int u = edge_u(edge);
        const int v = edge_v(edge);
        edges[cursor[u]++] = v;
        edges[cursor[v]++] = u;
    }
}


// ============================================================
// Print edge list
// ============================================================

inline void undirected_graph::print_edgelist() const
{
    for (std::uint64_t edge : edgelist) {

        std::cout
            << "("
            << edge_u(edge)
            << ", "
            << edge_v(edge)
            << ")\n";
    }

    std::cout << std::endl;
}


// ============================================================
// Basic statistics
// ============================================================

inline void undirected_graph::basic_stats() const
{
    const std::string border =
        "========================================";

    std::cout
        << border << "\n"
        << "       Graph Properties\n"
        << border << "\n\n"
        << "Graph reading completed in "
        << read_duration.count()
        << " seconds\n"
        << "|V|: "
        << numVert
        << "\n"
        << "|E|: "
        << edgelist.size()
        << "\n"
        << border
        << "\n\n";
}

#endif // GRAPH_HXX