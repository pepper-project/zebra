#include "verifier_precomp.h"
#include <crypto/prng.h>
#include <iostream>
#include <common/math.h>
#include <cassert>
using namespace std;

extern Prng prng;
Prng prng(PNG_CHACHA);
void VerifierPrecomputation::init(PWSCircuit* subcircuit) {

    depth = subcircuit->depth();

    layerSizes = new int[depth];
    logLayerSizes = new int[depth];
    for (int i = 0; i < depth; i++) {
        layerSizes[i] = (*subcircuit)[i].size();
        logLayerSizes[i] = ((*subcircuit)[i].logSize());
    }

    this->subcircuit = subcircuit;

    add.resize(depth - 1 );
    mul.resize(depth - 1 );
    sub.resize(depth - 1 );
    muxl.resize(depth - 1 );
    muxr.resize(depth - 1 );
    tau.resize(depth - 1 );

    qi = new MPZVector[depth];
    ri = new MPZVector[depth];

    //Note the sizes here... we don't need an ri for the output layer.
    //the choice of notation will allow for notation consistent with
    //published work, e.g. qi[1] is a function of ri[0], tau[0].

    qi[0].resize((*subcircuit)[0].logSize());

    for (int i = 1; i < depth; i++) {
        qi[i].resize( (*subcircuit)[i].logSize());
        ri[i-1].resize(2 * (*subcircuit)[i].logSize());
    }
    m_setup = 0;
    initialized = true;

}

void VerifierPrecomputation::deinit(void) {
    delete[] layerSizes;
    delete[] logLayerSizes;
    delete[] qi;
    delete[] ri;
}

void VerifierPrecomputation::flipAllCoins() {
    if (!initialized) {
        cout << "ERROR: call init() on VerifierPrecompuation first" << endl;
        exit(1);
    }

    //q0 doesn't depend on anything.
    int qi0size = qi[0].size();
    for (int i = 0; i < qi0size; i++) {
        prng.get_random(qi[0][i], subcircuit->prime);
/*
// no need for this; it gets dumped out as w0
#ifdef DEBUG
        gmp_printf("q0[%d]: %Zd\n", i,  qi[0][i]);
#endif
*/
    }

    //again note the indexing to avoid a fencepost problem.
    for (int i = 0; i < depth - 1; i++) {
        prng.get_random(tau[i], subcircuit->prime);

        int riSize = ri[i].size(); //2*logLayerSize.

        for (int j = 0; j < riSize; j++) {
            prng.get_random(ri[i][j], subcircuit->prime);
        }

    }

    //now compute qi's based on tau's, ri's.


    for (int i = 1; i < depth; i++) {

        int qiSize = qi[i].size();
        int offset = ri[i-1].size()/2; //ri = {w1, w2}.
        assert(qiSize == offset);

        //qi[i][j] = tau[i-1] * (ri[i-1][offset+j] - ri[i-1][j] ) + ri[i-1][j]
#ifdef DEBUG
        gmp_printf("tau[%d]: %Zd\n", i - 1, tau[i-1]);
#endif
        for (int j = 0; j < qiSize; j++) {
            mpz_sub(qi[i][j], ri[i-1][offset+j], ri[i-1][j]);
            mpz_mul(qi[i][j], tau[i-1], qi[i][j]);
            modadd(qi[i][j], ri[i-1][j], qi[i][j], subcircuit->prime);
        }
    }

#ifdef DEBUG
    cout << endl;
#endif
}

void VerifierPrecomputation::computeAddMul(vector<bool> muxBits) {

    if (!initialized) {
        cout << "ERROR: call init() on VerifierPrecompuation first" << endl;
        exit(1);
    }

    for (int i = 0; i < depth - 1; i++) {

        //first compute add and mul for the sub circuit.
        int inputLayerSize = (*subcircuit)[i+1].size();
        int logInputLayerSize = (*subcircuit)[i+1].logSize();
        int logOutputLayerSize = (*subcircuit)[i].logSize();

        MPZVector rand(logOutputLayerSize + 2 * logInputLayerSize);

        for (int j = 0; j < logOutputLayerSize; j++)
            mpz_set(rand[j], qi[i][j]);


        for (int j = 0; j < logInputLayerSize; j++) {
            mpz_set(rand[j+logOutputLayerSize], ri[i][j]);
            mpz_set(rand[j+logOutputLayerSize + logInputLayerSize], ri[i][j+logInputLayerSize]);
        }


        clock_gettime(CLOCK_REALTIME, &t1);
        for (int _i = 0; _i < NREPS; _i++) {
            (*subcircuit)[i].computeWirePredicates(add[i], mul[i], sub[i], muxl[i], muxr[i], muxBits, rand, inputLayerSize, subcircuit->prime);
        }
        clock_gettime(CLOCK_REALTIME, &t2);
        m_setup += ( (t2.tv_sec - t1.tv_sec) * BILLION  + t2.tv_nsec - t1.tv_nsec ) / (double) NREPS;



#ifdef DEBUG
        gmp_printf("add[%d]: %Zd\n", i, add[i]);
        gmp_printf("mul[%d]: %Zd\n", i, mul[i]);
        gmp_printf("sub[%d]: %Zd\n", i, sub[i]);
        gmp_printf("muxl[%d]: %Zd\n", i, muxl[i]);
        gmp_printf("muxr[%d]: %Zd\n", i, muxr[i]);

        int qiSize = qi[i].size();
        for (int j = 0; j < qiSize; j++) {
            gmp_printf("w0[%d]: %Zd\n", j, qi[i][j]);
        }

        int offset = ri[i].size()/2;
        for (int j = 0; j < offset; j++) {
            gmp_printf("w1[%d]: %Zd\n", j, ri[i][j]);
        }


        for (int j = 0; j < offset; j++) {
            gmp_printf("w2[%d]: %Zd\n", j, ri[i][j + offset]);
        }

        cout << endl;
#endif
    }

}
