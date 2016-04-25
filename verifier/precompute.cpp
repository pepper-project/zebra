// precompute.cpp
// commandline utility to precompute values for CMT V
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

#include "precompute.h"

using namespace std;

//
// invoke libcmtprecomp and dump out the results
//
int main (int argc, char* argv[]) {
    if (argc < 2) {
        cout << "usage: " << argv[0] << " <pwsfile>  [num instances]" << endl;
        exit(1);
    }

    cmtprecomp_init(argv[1]);

    int numInstances = 1;
    if (argc > 2) {
        numInstances = atoi(argv[2]);
    }

    cmtprecomp_cdata cdata;
    for (int i = 0; i < numInstances; i++) {
        cmtprecomp_new(&cdata);

        if (i != 0) {
            gmp_printf(PRECOMP_SEPARATOR);
        }
        gmp_printf("# *** instance %d *** #\n", i);

        // per-layer values
        for (unsigned j = 0; j < cdata.depth; j++) {
            cmtprecomp_ldata &ldata = cdata.layers[j];
            gmp_printf("# *** layer %d *** #\n", j);
            gmp_printf("%Zx # tau[%d]\n", ldata.tau, j);
            gmp_printf("%Zx # add[%d]\n", ldata.add, j);
            gmp_printf("%Zx # mul[%d]\n", ldata.mul, j);
            gmp_printf("%Zx # sub[%d]\n", ldata.sub, j);
            gmp_printf("%Zx # muxl[%d]\n", ldata.muxl, j);
            gmp_printf("%Zx # muxr[%d]\n", ldata.muxr, j);
            gmp_printf("\n");

            // r and f_wt for each round
            for (unsigned k = 0; k < 2 * ldata.bSize; k++) {
                gmp_printf("%Zx # r[%d][%d]\n", ldata.r[k], j, k);
                for (int l = 0; l < 3; l++) {
                    gmp_printf("%Zx # f_wt[%d][%d][%d]\n", ldata.f_wt[3*k + l], j, k, l);
                }
                gmp_printf("\n");
            }

            // h_wt
            for (unsigned k = 0; k < ldata.hSize; k++) {
                gmp_printf("%Zx # h_wt[%d][%d]\n", ldata.h_wt[k], j, k);
            }
            gmp_printf("\n");
        }

        // q
        gmp_printf("# *** q0 *** #\n");
        for (unsigned k = 0; k < cdata.q0Size; k++) {
            gmp_printf("%Zx # q0[%d]\n", cdata.q0[k], k);
        }
        gmp_printf("\n");

        // input Lagrange weights
        gmp_printf("# *** input MLExt *** #\n");
        for (unsigned j = 0; j < cdata.iSize; j++) {
            gmp_printf("%Zx # X_i[%d]\n", cdata.chi_i[j], j);
        }
        gmp_printf("\n");

        // output Lagrange weights
        gmp_printf("# *** output MLExt *** #\n");
        for (unsigned j = 0; j < cdata.oSize; j++) {
            gmp_printf("%Zx # X_o[%d]\n", cdata.chi_o[j], j);
        }

        cmtprecomp_delete(&cdata);
    }

    cmtprecomp_deinit();
    return 0;
}
