/*Functionality : Given a graph with edges (u,v) add the duplicate edges (v,u) to an different file.
Update the number of edges to 2*edges in the first line.
*/
#include <iostream>
#include <fstream>
#include <vector>

int main(int argc, char* argv[]) {
    std::cout << "--------------------------------------------------------------------------\n"
          << "                  Welcome to the 'EdgeMirroring Program'\n"
          << "--------------------------------------------------------------------------\n"
          << "This program enhances graph structures. For each edge (u, v), a corresponding\n"
          << "reverse edge (v, u) is added to the graph, making it bidirectional.\n"
          << "--------------------------------------------------------------------------\n"
          << std::endl;

    std::string filename;

    if(argc < 2) {
        std::cout << "Please enter the path to the input file: ";
        std::cin >> filename;
    }
    else
        filename = argv[1];

    std::ifstream inputFile(filename);

    if (!inputFile) {
        std::cerr << "\nUnable to open the file: " << filename << std::endl;
        return 1; // Typically, returning non-zero from `main` indicates an error.
    }

    int vertices, edges;
    int u, v;
    inputFile >> vertices >> edges;
    std::vector<std::vector<int> > adjlist(vertices);
    for(int i = 0; i < edges; ++i) {
        inputFile >> u >> v;
        std::cout << u << " " << v << std::endl;
        adjlist[u].push_back(v);
        adjlist[v].push_back(u);
    }
    inputFile.close();
    std::ofstream outFile(filename);
    if(!outFile) {
        std::cerr <<"\nUnable to open the file for writing.";
        return 0;
    }
    outFile << vertices <<" " << 2*edges <<std::endl;
    for(int i = 0; i < adjlist.size(); ++i) {
        for(int j = 0; j < adjlist[i].size(); ++j) {
            outFile << i << " " << adjlist[i][j] << std::endl;
        }
    }
    outFile.close();
    return 0;
}