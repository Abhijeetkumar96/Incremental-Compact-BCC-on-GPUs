#include "parlay/sequence.h"
#include "parlay/parallel.h"

#ifndef CC_HPP
#define CC_HPP

long connect_it(
	int n, long m, 
	parlay::sequence<uint64_t>& h_edgelist, 
	parlay::sequence<int>& labels, 
	parlay::sequence<int>& parents, 
	parlay::sequence<uint64_t>& sptree);

#endif // CC_HPP