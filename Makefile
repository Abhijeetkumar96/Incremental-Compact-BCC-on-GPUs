# Mother Makefile: builds each implementation through its own Makefile, then
# links them into the single ./run_all driver.
#
#   make SM=80      # A100
#   make SM=89      # L40 / L40S
#   make SM=90      # H100
#
# Prefer `python3 run.py ...`, which detects SM automatically.

SM ?= 89

CPU_DIR := baseline/HRBK22_dynamic_bcc
STATIC_DIR := baseline/static-compact-bcc
GPU_DIR := incremental_dynamic
BUILD := build

CXX := g++
CXXFLAGS := -std=c++17 -O3 -Icommon -I$(GPU_DIR)/include -I$(CPU_DIR)

CPU_LIB := $(CPU_DIR)/libhrbk22.a
GPU_LIB := $(GPU_DIR)/obj/libgpubcc.a

TARGET := run_all

.PHONY: all cpu gpu static standalone clean help

all: $(TARGET) static

cpu:
	$(MAKE) -C $(CPU_DIR) lib

gpu:
	$(MAKE) -C $(GPU_DIR) SM=$(SM) opt-lib

# Static GPU BCC reference; standalone binary at $(STATIC_DIR)/bin/cuda_bcc.
static:
	$(MAKE) -C $(STATIC_DIR) SM=$(SM) opt

$(BUILD)/run_all.o: driver/run_all.cpp common/graph_input.hpp $(GPU_DIR)/include/gpu_bcc_runner.hpp $(CPU_DIR)/hrbk22.hpp
	@mkdir -p $(BUILD)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(TARGET): cpu gpu $(BUILD)/run_all.o
	nvcc -arch=sm_$(SM) $(BUILD)/run_all.o $(GPU_LIB) $(CPU_LIB) -o $@ -lpthread

# Individual executables (incremental_dynamic/bin/cuda_bcc and the CPU baseline's ./main).
standalone:
	$(MAKE) -C $(CPU_DIR)
	$(MAKE) -C $(GPU_DIR) SM=$(SM) opt

clean:
	$(MAKE) -C $(CPU_DIR) clean
	$(MAKE) -C $(GPU_DIR) clean
	$(MAKE) -C $(STATIC_DIR) clean
	rm -rf $(TARGET) $(BUILD)

help:
	@echo "make [SM=80|86|89|90]  - build ./run_all (CPU baseline + GPU) and static-compact-bcc"
	@echo "make static            - build only baseline/static-compact-bcc"
	@echo "make standalone        - build the per-implementation executables"
	@echo "make clean             - clean everything"
