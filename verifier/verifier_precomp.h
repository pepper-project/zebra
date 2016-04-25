/*
 verifier_precomp.h 

 Given a subcircuit specified by a pws file and a number of times to
 repeat that subcircuit in parallel, this class chooses and stores all
 of V's randomness, and precomputes the multilinear extensions of add
 and mul at each layer.

 */

#pragma once

#include <circuit/pws_circuit.h>
#include <vector>

extern "C" {
#include "util.h"
}
#include <time.h>
class VerifierPrecomputation {

  
 public:
    
    void init(PWSCircuit* subcircuit);
    void deinit(void);
    void flipAllCoins();
    void computeAddMul(std::vector<bool> muxBits);

    MPZVector add; //val of add(w0, w1, w2) at each layer. e.g. add[0] = add~(qi[0], ri[0])
    MPZVector mul;   
    MPZVector sub;
    MPZVector muxl;
    MPZVector muxr;
    MPZVector* qi; //aka w0, q1 = (w2 - w1) *  tau[0] + w1.
    MPZVector* ri; //aka {w1, w2}
    MPZVector tau; 
    int* layerSizes;
    int* logLayerSizes;
    int depth;
    PWSCircuit* subcircuit; 
    double m_setup;
 private:
    bool initialized;
    
    struct timespec t1, t2;
   
};
