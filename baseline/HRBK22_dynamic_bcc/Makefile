CXX ?= g++
CXXFLAGS ?= -std=c++17 -O3
CXXFLAGS += -I../../common
LDLIBS += -pthread

TARGET := main
DEBUG_TARGET := main-debug
LIB := libhrbk22.a
LIB_SOURCES := hrbk22.cpp cc.cpp
LIB_OBJECTS := $(LIB_SOURCES:.cpp=.o)
HEADERS := hrbk22.hpp spanning_tree.hxx lca.hxx cc.hpp bridge.h ../../common/graph_input.hpp

.PHONY: all lib debug clean

all: $(TARGET)

# Library consumed by the top-level run_all driver.
lib: $(LIB)

debug: $(DEBUG_TARGET)

%.o: %.cpp $(HEADERS)
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(LIB): $(LIB_OBJECTS)
	ar rcs $@ $^

$(TARGET): main.cpp $(LIB)
	$(CXX) $(CXXFLAGS) main.cpp $(LIB) -o $@ $(LDLIBS)

$(DEBUG_TARGET): main.cpp $(LIB_SOURCES) $(HEADERS)
	$(CXX) $(CXXFLAGS) -DDEBUG main.cpp $(LIB_SOURCES) -o $@ $(LDLIBS)

clean:
	rm -f $(TARGET) $(DEBUG_TARGET) $(LIB) $(LIB_OBJECTS)
	rm -rf $(TARGET).dSYM $(DEBUG_TARGET).dSYM
