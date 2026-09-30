#ifndef SPANNING_TREE_HXX
#define SPANNING_TREE_HXX

#include "graph_input.hpp"

#include <vector>
#include <queue>
#include <stdexcept>


// ============================================================
// Build a rooted spanning tree
//
// BFS straight over the graph's CSR adjacency, so no per call
// adjacency structure is built.
//
// Vertices unreachable from root keep parent = depth = -1.
// ============================================================

inline void build_rooted_spanning_tree(
    const GraphInput& graph,
    int root,
    std::vector<int>& parent,
    std::vector<int>& depth)
{
    const long n = graph.numVert;

    if (root < 0 || root >= n) {
        throw std::out_of_range(
            "root vertex out of range");
    }

    parent.assign(n, -1);
    depth.assign(n, -1);

    const std::vector<long>& off = graph.offsets;
    const std::vector<int>& nbr = graph.neighbors;

    std::queue<int> q;

    parent[root] = root;
    depth[root] = 0;

    q.push(root);

    while (!q.empty()) {

        int u = q.front();
        q.pop();

        for (long j = off[u]; j < off[u + 1]; ++j) {

            int v = nbr[j];

            if (parent[v] != -1)
                continue;

            parent[v] = u;
            depth[v] = depth[u] + 1;

            q.push(v);
        }
    }
}

#endif // SPANNING_TREE_HXX