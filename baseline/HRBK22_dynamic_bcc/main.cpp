#include "graph_input.hpp"
#include "hrbk22.hpp"

#include <exception>
#include <iostream>
#include <string>

int main(int argc, char** argv)
{
    if (argc < 3 || argc > 4) {
        std::cerr
            << "Usage: "
            << argv[0]
            << " <graph> <batch size> [seed]\n";

        return 1;
    }

    try {
        const int k = std::stoi(argv[2]);

        if (k < 0) {
            std::cerr << "batch size must be non-negative\n";
            return 1;
        }

        const std::uint64_t seed =
            argc == 4 ? std::stoull(argv[3]) : 12345;

        const GraphInput graph = read_graph(argv[1]);
        const auto batch = generate_batch(graph, k, seed);

        std::cout << "|V|: " << graph.numVert
                  << ", |E|: " << graph.numEdges()
                  << ", batch: " << batch.size() << " new edges\n";

        const Hrbk22Result result = run_hrbk22(graph, batch);

        std::cout << "Batch processing time: " << result.batch_ms << " ms\n"
                  << "Cut vertices: " << result.num_cut_vertices << "\n";
    }
    catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return 1;
    }

    return 0;
}
