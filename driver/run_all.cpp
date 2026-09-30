// Single entry point: reads the graph once, generates the batch once, and runs
// every implementation on the same in-memory input.

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <exception>
#include <iostream>
#include <string>

#include "graph_input.hpp"
#include "hrbk22.hpp"
#include "gpu_bcc_runner.hpp"

namespace {

const char* usage =
    "Usage: run_all -i <graph> [options]\n"
    "  -i <graph>    input graph (.txt/.edges/.eg2 edge list or .egr/.bin/.csr)\n"
    "  -k <n>        batch size: random new edges to insert (default 0)\n"
    "  -o <dir>      write GPU result files to <dir>\n";

double ms_since(std::chrono::steady_clock::time_point start)
{
    return std::chrono::duration<double, std::milli>(
        std::chrono::steady_clock::now() - start).count();
}

} // namespace

int main(int argc, char** argv)
{
    std::string input;
    int k = 0;
    GpuBccOptions gpu_options;

    try {
        for (int i = 1; i < argc; ++i) {
            const std::string arg = argv[i];
            const bool has_value = i + 1 < argc;

            if (arg == "-i" && has_value)       input = argv[++i];
            else if (arg == "-k" && has_value)  k = std::stoi(argv[++i]);
            else if (arg == "-o" && has_value) {
                gpu_options.write_output = true;
                gpu_options.output_directory = argv[++i];
                if (gpu_options.output_directory.back() != '/')
                    gpu_options.output_directory += '/';
            }
            else if (arg == "-h" || arg == "--help") {
                std::cout << usage;
                return EXIT_SUCCESS;
            }
            else {
                std::cerr << "Unknown or incomplete argument: " << arg << "\n" << usage;
                return EXIT_FAILURE;
            }
        }
    }
    catch (const std::exception&) {
        std::cerr << "Invalid numeric argument\n" << usage;
        return EXIT_FAILURE;
    }

    if (input.empty() || k < 0) {
        std::cerr << usage;
        return EXIT_FAILURE;
    }

    try {
        auto t = std::chrono::steady_clock::now();
        const GraphInput graph = read_graph(input);
        const double read_ms = ms_since(t);

        t = std::chrono::steady_clock::now();
        const auto batch = generate_batch(graph, k);
        const double gen_ms = ms_since(t);

        std::cout << "Graph: " << input << "\n"
                  << "  |V| = " << graph.numVert << ", |E| = " << graph.numEdges()
                  << " (read in " << read_ms << " ms)\n"
                  << "Batch: requested " << k << ", generated " << batch.size()
                  << " distinct new edges (" << gen_ms << " ms)\n";

        std::cout << "\n[CPU] HRBK22 dynamic BCC\n";
        const Hrbk22Result cpu = run_hrbk22(graph, batch);
        std::cout << "[CPU] batch time: " << cpu.batch_ms << " ms, cut vertices: "
                  << cpu.num_cut_vertices << "\n";

        std::cout << "\n[GPU] incremental compact BCC\n";
        const GpuBccResult gpu = run_gpu_bcc(graph, batch, gpu_options);
        std::cout << "[GPU] batch time: " << gpu.batch_ms << " ms, cut vertices: "
                  << gpu.num_cut_vertices << "\n";

        std::cout << "\nSummary\n"
                  << "  CPU batch: " << cpu.batch_ms << " ms\n"
                  << "  GPU batch: " << gpu.batch_ms << " ms\n";
        if (gpu.batch_ms > 0.0)
            std::cout << "  Speedup  : " << cpu.batch_ms / gpu.batch_ms << "x\n";
        std::cout << "  Cut vertex count "
                  << (cpu.num_cut_vertices == gpu.num_cut_vertices ? "MATCH" : "MISMATCH")
                  << " (" << cpu.num_cut_vertices << " vs " << gpu.num_cut_vertices << ")\n";
    }
    catch (const std::exception& e) {
        std::cerr << "Error: " << e.what() << "\n";
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
