// cmtprecomp_private.h
// private header file for libcmtprecomp
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

#include <gmp.h>

#include <cstdbool>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <unistd.h>
#include <iostream>
#include <vector>

#include "verifier_precomp.h"

#define INHIBIT_MPFQ
extern "C" {
#include "util.h"
}

#include <circuit/pws_circuit_parser.h>
#include <circuit/pws_circuit.h>
#include <common/math.h>
#include <common/poly_utils.h>
#include "cmtprecomp.h"

// globals live in the CMTPrecompState singleton
class CMTPrecompState {
    public:
        PWSCircuitParser *parser;
        PWSCircuit *c;
        std::vector<bool> muxBits;
};

CMTPrecompState state;
