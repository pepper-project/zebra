// cmtprecomp.h
// public header file for libcmtprecomp
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

#ifndef have_cmtprecomp_h
#define have_cmtprecomp_h
#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

// per-layer precomputed data
typedef struct {
    unsigned bSize;
    unsigned hSize;

    // per-layer
    mpz_t tau;
    mpz_t add;
    mpz_t mul;
    mpz_t sub;
    mpz_t muxl;
    mpz_t muxr;
    mpz_t *h_wt;    // hSize

    // per-round
    mpz_t *r;       //     2 * bSize
    mpz_t *f_wt;    // 3 * 2 * bSize
} cmtprecomp_ldata;

// per-circuit precomputed data
typedef struct {
    unsigned depth;
    unsigned maxWidth; //added for easy cmt_io initialization
    unsigned q0Size;
    unsigned iSize;
    unsigned oSize;

    bool* muxBits;
    unsigned numMuxBits;
    // per-circuit
    mpz_t *q0;
    mpz_t *chi_i;   // iSize
    mpz_t *chi_o;   // oSize

    // per-layer
    cmtprecomp_ldata *layers;   // depth

    // state of computation
    unsigned cLayer;
    unsigned cRound;
    unsigned cPhase;

    bool initialized;
} cmtprecomp_cdata;

// call before doing anything else
extern void cmtprecomp_init(char *pwsfile);

// call when you're done
extern void cmtprecomp_deinit(void);

// set the value of the mux bits
extern void cmtprecomp_setmuxbits(bool *bits);

// fetches the mux bits. Note the caller is responsible for freeing
// the returned bits. (Why make a copy? because the state uses a
// bool<vector> to store the mux bits, and bool<vector> doesn't
// implement the data() method for retrieving the underlying array)
extern void cmtprecomp_getmuxbits(bool** bits, int* numBits);


// call to fill a struct with new data
extern int cmtprecomp_new(cmtprecomp_cdata *cdata);

// call to clean up the struct
extern void cmtprecomp_delete(cmtprecomp_cdata *cdata);

// not strictly related to precomp, but I need the cpp interfaces.
extern void generate_inputs(mpz_t * inputs, int id);

#ifdef __cplusplus
}
#endif // __cplusplu
#endif // _cmtprecomp_h
