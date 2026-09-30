// Standalone GPU entry point. The top-level run_all driver calls run_gpu_bcc directly.

#include <exception>
#include <iostream>

#include "graph_input.hpp"
#include "gpu_bcc_runner.hpp"
#include "CommandLineParser.cuh"

int main(int argc, char* argv[]) {
	std::ios_base::sync_with_stdio(false);
	CommandLineParser cmdParser(argc, argv);
	const auto& args = cmdParser.getArgs();

	if (args.error) {
		std::cerr << CommandLineParser::help_msg << std::endl;
		return EXIT_FAILURE;
	}

	try {
		const GraphInput graph = read_graph(args.inputFile);
		const auto batch = generate_batch(graph, args.batchSize);

		std::cout << "|V|: " << graph.numVert << ", |E|: " << graph.numEdges()
				  << ", batch: " << batch.size() << " new edges\n";

		GpuBccOptions options;
		options.write_output = args.write_output;
		options.output_directory = args.output_directory;

		const GpuBccResult result = run_gpu_bcc(graph, batch, options);

		std::cout << "Batch processing time: " << result.batch_ms << " ms\n"
				  << "Cut vertices: " << result.num_cut_vertices << "\n";
	}
	catch (const std::exception& e) {
		std::cerr << "Error: " << e.what() << "\n";
		return EXIT_FAILURE;
	}

	return EXIT_SUCCESS;
}
