CXX ?= g++
CXXFLAGS ?= -std=c++17 -O3

TARGET := main
DEBUG_TARGET := main-debug
SOURCES := main.cpp cc.cpp
HEADERS := graph.hxx spanning_tree.hxx lca.hxx cc.hpp bridge.h

.PHONY: all debug clean

all: $(TARGET)

debug: $(DEBUG_TARGET)

$(TARGET): $(SOURCES) $(HEADERS)
	$(CXX) $(CXXFLAGS) $(SOURCES) -o $@

$(DEBUG_TARGET): $(SOURCES) $(HEADERS)
	$(CXX) $(CXXFLAGS) -DDEBUG $(SOURCES) -o $@

clean:
	rm -f $(TARGET) $(DEBUG_TARGET)
	rm -rf $(TARGET).dSYM $(DEBUG_TARGET).dSYM
