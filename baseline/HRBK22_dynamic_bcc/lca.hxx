#ifndef LCA_HXX
#define LCA_HXX

#include <iostream>
#include <algorithm>
#include <stdexcept>
#include <utility>
#include <vector>

extern std::vector<int> in_fundamental_cycle;
extern std::vector<int> is_safe;
extern std::vector<int> is_lca;
extern std::vector<uint64_t> edge_base_vertices;
extern std::vector<int> is_base_vertex;

inline void lca(
    int u,
    int v,
    int edge_id,
    const std::vector<int>& parent,
    const std::vector<int>& depth) 
    {
    if(parent[u] == v || parent[v] == u)
        return;

    // std::cout << "\n\nProcessing edge (" << u << ", " << v << ")\n";
    // std::cout << "Initial depths: u=" << depth[u] << ", v=" << depth[v] << "\n";
    
    while (parent[u] != parent[v]) {
        if (depth[u] > depth[v]) {
            // std::cout << "Moving up from " << u << " to " << parent[u] << "\n";
            in_fundamental_cycle[u] = true;
            is_safe[u] = true;
            u = parent[u];
        } else {
            // std::cout << "Moving up from " << v << " to " << parent[v] << "\n";
            in_fundamental_cycle[v] = true;
            is_safe[v] = true;
            v = parent[v];
        }
    }
    // std::cout << "Final positions: u=" << u << ", v=" << v << "\n\n";
    in_fundamental_cycle[u] = true;
    in_fundamental_cycle[v] = true;

    is_lca[parent[u]] = true;
    edge_base_vertices[edge_id] = (static_cast<uint64_t>(u) << 32) | static_cast<uint64_t>(v);
    is_base_vertex[u] = true;
    is_base_vertex[v] = true;
}

#endif // LCA_HXX