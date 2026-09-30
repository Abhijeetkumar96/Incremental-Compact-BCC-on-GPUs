# GPU incremental BCC. Invoked by the top-level Makefile as `make -C incremental_dynamic SM=<cc>`.
# SM is the compute capability without the dot, e.g. 80 (A100), 89 (L40/L40S), 90 (H100).

SM ?= 89

COMMON := ../common

NVCCFLAGS := -std=c++17 -arch=sm_$(SM) -Iinclude -I$(COMMON)
CPPFLAGS := -std=c++17 -Iinclude -I$(COMMON)

OBJDIR := obj
SRCDIR := src
INCDIR := include
BINDIR := bin

# Create the obj directory if it doesn't exist
$(shell mkdir -p $(OBJDIR))
$(shell mkdir -p $(BINDIR))

# Everything except the standalone main; linked into both cuda_bcc and run_all.
LIB_OBJECTS := $(OBJDIR)/gpu_bcc_runner.o $(OBJDIR)/bcc.o $(OBJDIR)/utility.o $(OBJDIR)/bfs.o \
			   $(OBJDIR)/lca.o $(OBJDIR)/cut_vertex.o $(OBJDIR)/cc.o $(OBJDIR)/bcc_memory_utils.o
LIB := $(OBJDIR)/libgpubcc.a

# Rebuild everything when the target architecture changes.
ARCH_STAMP := $(OBJDIR)/.sm_$(SM)

all: opt-parallel

$(ARCH_STAMP):
	rm -f $(LIB_OBJECTS) $(OBJDIR)/main.o $(OBJDIR)/.sm_* $(LIB)
	touch $@

lib: $(LIB)

$(LIB): $(LIB_OBJECTS)
	ar rcs $@ $^

cuda_bcc: $(OBJDIR)/main.o $(LIB)
	nvcc $(NVCCFLAGS) $(OBJDIR)/main.o $(LIB) -o $(BINDIR)/cuda_bcc

$(OBJDIR)/main.o: main.cu $(INCDIR)/gpu_bcc_runner.hpp $(COMMON)/graph_input.hpp $(ARCH_STAMP)
	nvcc $(NVCCFLAGS) -c main.cu -o $@

$(OBJDIR)/gpu_bcc_runner.o: $(SRCDIR)/gpu_bcc_runner.cu $(INCDIR)/gpu_bcc_runner.hpp $(COMMON)/graph_input.hpp $(ARCH_STAMP)
	nvcc $(NVCCFLAGS) -c $< -o $@

$(OBJDIR)/bcc.o: $(SRCDIR)/bcc.cu $(INCDIR)/bcc.cuh $(ARCH_STAMP)
	nvcc $(NVCCFLAGS) -c $< -o $@

$(OBJDIR)/bcc_memory_utils.o: $(SRCDIR)/bcc_memory_utils.cu $(INCDIR)/bcc_memory_utils.cuh $(ARCH_STAMP)
	nvcc $(NVCCFLAGS) -c $< -o $@

$(OBJDIR)/bfs.o: $(SRCDIR)/bfs.cu $(INCDIR)/bfs.cuh $(ARCH_STAMP)
	nvcc $(NVCCFLAGS) -c $< -o $@

$(OBJDIR)/utility.o: $(SRCDIR)/utility.cpp $(INCDIR)/utility.hpp $(ARCH_STAMP)
	g++ $(CPPFLAGS) -c $< -o $@

$(OBJDIR)/lca.o: $(SRCDIR)/lca.cu $(INCDIR)/lca.cuh $(ARCH_STAMP)
	nvcc $(NVCCFLAGS) -c $< -o $@

$(OBJDIR)/cc.o: $(SRCDIR)/connected_components.cu $(INCDIR)/connected_components.cuh $(ARCH_STAMP)
	nvcc $(NVCCFLAGS) -c $< -o $@

$(OBJDIR)/cut_vertex.o: $(SRCDIR)/cut_vertex.cu $(INCDIR)/cut_vertex.cuh $(ARCH_STAMP)
	nvcc $(NVCCFLAGS) -c $< -o $@

serial_BCC: src/Serial_BCC_v1.cpp
	g++ -std=c++17 -O3 src/Serial_BCC_v1.cpp -o $(BINDIR)/serial_BCC

checker: implicit_bcc_checker.o explicit_bcc_checker.o

implicit_bcc_checker.o:
	g++ -std=c++17 -O3 src/checker_v1.cpp -o $(BINDIR)/implicit_bcc_checker

explicit_bcc_checker.o:
	g++ -std=c++17 -O3 src/explicit_bcc_checker.cpp -o $(BINDIR)/explicit_bcc_checker

clean:
	rm -rf $(OBJDIR)/*.o $(OBJDIR)/.sm_* $(LIB) $(BINDIR)/*

# Target to add -O3 optimization flag
opt: NVCCFLAGS += -O3
opt: CPPFLAGS += -O3
opt: cuda_bcc serial_BCC checker

opt-lib: NVCCFLAGS += -O3
opt-lib: CPPFLAGS += -O3
opt-lib: lib

opt-parallel:
	$(MAKE) opt -j$(shell nproc)

# Help target for displaying usage information
help:
	@echo "Available commands (make [command] [SM=80|86|89|90]):"
	@echo "  all          - Compiles the main CUDA program and associated utilities"
	@echo "  cuda_bcc     - Compiles the standalone CUDA BCC program"
	@echo "  lib          - Builds obj/libgpubcc.a (used by the top-level run_all)"
	@echo "  opt-lib      - Same as lib with -O3"
	@echo "  checker      - Compiles the implicit BCC checker"
	@echo "  serial_BCC   - Compiles the serial BCC algorithm implementation"
	@echo "  opt          - Builds all targets with optimization (-O3)"
	@echo "  opt-parallel - Builds all targets with optimization (-O3) in parallel"
	@echo "  clean        - Removes all compiled files"
	@echo "  help         - Shows this help message"

.PHONY: all lib opt opt-lib clean help opt-parallel cuda_bcc serial_BCC checker
