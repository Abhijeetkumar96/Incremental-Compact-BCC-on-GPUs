# Incremental Compact BCC

GPU incremental biconnected-components (cut-vertex) computation, benchmarked against a CPU
dynamic baseline (HRBK22) and a static GPU baseline (static-compact-bcc).

## Layout
```
incremental_dynamic/   GPU incremental BCC (main code): src/, include/, main.cu, Makefile
baseline/
  HRBK22_dynamic_bcc/  CPU dynamic BCC baseline (ParlayLib)
  static-compact-bcc/  Static GPU BCC baseline
common/                Shared graph reader + batch generator (graph_input.hpp)
driver/                run_all.cpp: single binary running CPU baseline + GPU on the same input
datasets/              small_datasets/ (text) and medium_datasets/ (.egr binary CSR)
Makefile               Top-level build (calls each sub-Makefile)
run.py                 Build + run everything
```

## Requirements
- CUDA Toolkit 11+ (`nvcc`) and an NVIDIA GPU (sm_70 or newer)
- g++ with C++17
- Python 3 (for `run.py`)

## Quick start
```shell
python3 run.py datasets/small_datasets/input_100.txt -k 10
```
This will:
1. detect the GPU's compute capability via `nvidia-smi` (A100 -> 80, L40/L40S -> 89, H100 -> 90, ...),
2. run `make SM=<cc>` at the top level,
3. run `./run_all` (CPU baseline + GPU incremental on the same graph and batch),
4. run `baseline/static-compact-bcc/bin/cuda_bcc` on the same graph.

`run.py` options:

| Option        | Meaning                                                   |
|---------------|-----------------------------------------------------------|
| `-k N`        | batch size: N random new edges to insert (default 0)      |
| `-o DIR`      | write GPU result files (cut vertices, BCC labels) to DIR  |
| `--sm CC`     | skip detection and build for compute capability CC (e.g. `80`) |
| `--no-build`  | skip `make`, just run                                     |
| `-j N`        | parallel make jobs (default: all cores)                   |

Pick the GPU with `CUDA_VISIBLE_DEVICES` (the code itself never selects a device):
```shell
CUDA_VISIBLE_DEVICES=1 python3 run.py datasets/medium_datasets/road_usa.egr -k 1000
```

## Building manually
```shell
make SM=89            # ./run_all + static-compact-bcc
make SM=80 static     # only baseline/static-compact-bcc
make SM=89 standalone # per-implementation executables (see below)
make clean            # clean all sub-projects
```
`SM` is the compute capability without the dot. Changing it triggers a full rebuild.

## Running manually
```shell
./run_all -i datasets/small_datasets/input_100.txt -k 10 [-o output/]
```
The graph is read once and the batch (seed 12345, deterministic) is generated once; both
implementations receive the same in-memory input. Output ends with a summary: CPU and GPU batch
times, speedup, and whether the cut-vertex counts match.

Standalone executables (after `make standalone`):
```shell
incremental_dynamic/bin/cuda_bcc -i <graph> -k <batch> [-o <dir>]
baseline/HRBK22_dynamic_bcc/main <graph> <batch> [seed]
baseline/static-compact-bcc/bin/cuda_bcc -i <graph>
```

## Input formats
Chosen by file extension:
- `.txt`, `.edges`, `.eg2`: text; first line `numVertices numDirectedEdges`, then one `u v` per line,
  with both `(u,v)` and `(v,u)` present.
- `.egr`, `.bin`, `.csr`: ECL binary CSR (`size_t` #offsets, `size_t` #neighbors, `long` offsets[], `int` neighbors[]).

Start with `datasets/small_datasets/` (e.g. `input_100.txt`, `triangle_cut.txt`) before the medium graphs.

## License
Unlicensed
