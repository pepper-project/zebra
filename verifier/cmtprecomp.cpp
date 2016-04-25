// libcmtprecomp
// shared library for doing precomputations for CMT
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

#include "cmtprecomp_private.h"

using namespace std;

//
// Get the parser set up, and parse the pwsfile
//
void cmtprecomp_init(char *pwsfile) {
    // initialize local variables
    mpz_t prime;
    mpz_init_set_ui(prime, 1);
    mpz_mul_2exp(prime, prime, PRIMEBITS);
    mpz_sub_ui(prime, prime, PRIMEDELTA);

    state.parser = new PWSCircuitParser(prime);
    state.c = new PWSCircuit(*state.parser);

    state.parser->parse(pwsfile);
    state.c->construct();

    // allocate and initialize mux bits
    int numMuxBits = state.parser->largestMuxBitIndex + 1;
    state.muxBits.reserve(numMuxBits);

    for (int i = 0; i < numMuxBits; i++) {
        state.muxBits[i] = i % 2;
    }

    mpz_clear(prime);
    return;
}

//
// clean up the parser and circuit objects
//
void cmtprecomp_deinit(void) {
    delete state.c;
    delete state.parser;

    return;
}

void cmtprecomp_setmuxbits(bool *bits) {
    int numMuxBits = state.parser->largestMuxBitIndex + 1;
    for (int i = 0; i < numMuxBits; i++) {
        state.muxBits[i] = bits[i];
    }

    return;
}

void cmtprecomp_getmuxbits(bool** bits, int* numBits) {
    *numBits = (state.parser->largestMuxBitIndex) ? (state.parser->largestMuxBitIndex)  + 1: 0;
    *bits = new bool[*numBits];
    for (int i = 0; i < *numBits; i++) {
        (*bits)[i] = state.muxBits[i];
    }
    return;
}

int cmtprecomp_new(cmtprecomp_cdata *cdata) {
    VerifierPrecomputation p;
    p.init(state.c);
    p.flipAllCoins();
    p.computeAddMul(state.muxBits);

    cdata->depth = p.depth - 1;
    cdata->q0Size = p.qi[0].size();
    cdata->iSize = p.layerSizes[cdata->depth];
    cdata->oSize = p.layerSizes[0];

    cdata->chi_i = cdata->chi_o = NULL;
    cdata->layers = NULL;

    // TODO lazy: we don't try to unwind memory allocations if something goes wrong
    if ( NULL == (cdata->q0 = (mpz_t *) malloc(cdata->q0Size * sizeof(mpz_t))) ||
         NULL == (cdata->chi_i = (mpz_t *) malloc(cdata->iSize * sizeof(mpz_t))) ||
         NULL == (cdata->chi_o = (mpz_t *) malloc(cdata->oSize * sizeof(mpz_t))) ||
         NULL == (cdata->layers = (cmtprecomp_ldata *) malloc(cdata->depth * sizeof(cmtprecomp_ldata))) ) {
        p.deinit();
        return 1;
    }

    // q0 - first layer q values, don't need the rest
    // (P computes the rest of them from w1, w2, and tau;
    // meanwhile, V has already used them in precomputation)
    for (unsigned i = 0; i < cdata->q0Size; i++) {
        mpz_init_set(cdata->q0[i], p.qi[0][i]);
    }

    // input multilinear extension Lagrange weights
    MPZVector chi_i(cdata->iSize);
    computeChiAll(chi_i, p.qi[cdata->depth], p.subcircuit->prime);
    for (unsigned i = 0; i < cdata->iSize; i++) {
        mpz_init_set(cdata->chi_i[i], chi_i[i]);
    }

    // output multilinear extension Lagrange weights
    MPZVector chi_o(cdata->oSize);
    computeChiAll(chi_o, p.qi[0], p.subcircuit->prime);
    for (unsigned i = 0; i < cdata->oSize; i++) {
        mpz_init_set(cdata->chi_o[i], chi_o[i]);
    }

    // per-layer values
    cdata->maxWidth = 0;
    for (unsigned j = 0; j < cdata->depth; j++) {
        cmtprecomp_ldata &layer = cdata->layers[j];
        cdata->maxWidth = max(cdata->maxWidth, (unsigned) p.layerSizes[j]);
        layer.bSize = p.ri[j].size() / 2;
        layer.hSize = p.logLayerSizes[j+1] + 1;

        // TODO lazy: we don't try to unwind memory allocations if something goes wrong
        if ( NULL == (layer.h_wt = (mpz_t *) malloc(layer.hSize * sizeof(mpz_t))) ||
             NULL == (layer.r = (mpz_t *) malloc(2 * layer.bSize * sizeof(mpz_t))) ||
             NULL == (layer.f_wt = (mpz_t *) malloc(3 * 2 * layer.bSize * sizeof(mpz_t))) ) {
            p.deinit();
            return 1;
        }

        mpz_init_set(layer.tau, p.tau[j]);
        mpz_init_set(layer.add, p.add[j]);
        mpz_init_set(layer.mul, p.mul[j]);
        mpz_init_set(layer.sub, p.sub[j]);
        mpz_init_set(layer.muxl, p.muxl[j]);
        mpz_init_set(layer.muxr, p.muxr[j]);

        // Lagrange weights for interpolating h
        MPZVector h_weights(layer.hSize);
        bary_precompute_weights(h_weights, p.tau[j], p.subcircuit->prime);
        for (unsigned k = 0; k < layer.hSize; k++) {
            mpz_init_set(layer.h_wt[k], h_weights[k]);
        }

        // values for r, and Lagrange weights for f
        for (unsigned k = 0; k < 2 * layer.bSize; k++) {
            mpz_init_set(layer.r[k], p.ri[j][k]);
            MPZVector weights(3);
            bary_precompute_weights3(weights, p.ri[j][k], p.subcircuit->prime);
            for (unsigned l = 0; l < 3; l++) {
                mpz_init_set(layer.f_wt[3 * k + l], weights[l]);
            }
        }
    }

    p.deinit();

    cdata->initialized = true;
    return 0;
}

void cmtprecomp_delete(cmtprecomp_cdata *cdata) {
    for (unsigned i = 0; i < cdata->depth; i++) {
        cmtprecomp_ldata &layer = cdata->layers[i];
        mpz_clears(layer.tau, layer.add, layer.mul, layer.sub, layer.muxl, layer.muxr, NULL);
        for (unsigned j = 0; j < 2 * layer.bSize; j++) {
            mpz_clear(layer.r[j]);
            for (unsigned k = 0; k < 3; k++) {
                mpz_clear(layer.f_wt[3 * j + k]);
            }
        }
        for (unsigned j = 0; j < layer.hSize; j++) {
            mpz_clear(layer.h_wt[j]);
        }

        free(layer.h_wt);
        free(layer.r);
        free(layer.f_wt);
    }

    for (unsigned i = 0; i < cdata->q0Size; i++) {
        mpz_clear(cdata->q0[i]);
    }
    for (unsigned i = 0; i < cdata->iSize; i++) {
        mpz_clear(cdata->chi_i[i]);
    }
    for (unsigned i = 0; i < cdata->oSize; i++) {
        mpz_clear(cdata->chi_o[i]);
    }

    free(cdata->layers);
    free(cdata->q0);
    free(cdata->chi_i);
    free(cdata->chi_o);

    cdata->initialized = false;
    return;
}

//This function is located here due to the need to properly set the
//input constants, by calling initalizeInputs()
void generate_inputs(mpz_t * inputs, int id) {

    MPQVector vec(state.c->getInputSize());
    for (size_t j = 0; j < vec.size(); j++)
        mpq_set_ui(vec[j],  (10 + id) * (j + 1), 1);

    //set the inputs to the computation, including the constants
    state.c->initializeInputs(vec);

    //now get the input layer and extract the full input, including
    //constants.
    CircuitLayer& inLayer = state.c->getInputLayer();

    mpz_t tmp;
    mpz_init(tmp);
    for (int j = 0; j < inLayer.size(); j++) {
        inLayer.gate(j).getValue(tmp);
        mpz_set(inputs[j], tmp);
    }
    mpz_clear(tmp);

}
