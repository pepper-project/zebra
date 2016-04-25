#pragma once
/* VerifierCompState: a class to hold the state of the cmt protocol
   for a particular instance of a computation and perform the protocol
   checks at the proper time. At the start of the protocol, it must be
   initialized with a VerifierPrecomp. 

   For the checking functions, after checking the request is valid and
   made at the proper time, the relavent mpz's are copied from the
   cmt_io_buf global variable, which is where the prover sends it's
   (potentially untrustworthy) responses. 

   For the send functions, after checking the request is valid, the
   required values are copied into the mpz_buf array, which can be
   sent to the prover.

 */
#include "mpfq/mpfq_p_25519.h"
extern "C" {
#include "util.h"

}

#include "verifier_precomp.h"


#include <time.h>



class VerifierCompState {
 public:
    //only default constructor. must call init() before using.     
    double  m_mlext_output, m_mlext_input, m_setup;
    double *m_sumcheck_modcmp, *m_sumcheck_extrap, *m_sumcheck_final;

    void init(VerifierPrecomputation* precomp, int comp_state_id);

    void checkOutputs(prover_request request);
    void checkF012(prover_request request);
    void checkH(prover_request request);

    void generateInputs(prover_request request);
    void sendQ0(prover_request request);
    void sendNextQI(prover_request request);
    void sendNextT(prover_request request);          
    void sendNextR(prover_request request);

    void doFinalCheck(void);
    void printStats(void);
 private:
    VerifierPrecomputation* precomp;
    MPZVector outputs;
    int currLayer;
    int currRound;
    int phase;
    int comp_state_id;
    mpz_t a, e;
    MPZVector inputs;
    bool successful;
    mpfq_p_25519_field theField;
    mpfq_p_25519_elt mpfq_e, mpfq_a;
    mpfq_p_25519_elt mpfq_tmp; 
    struct timespec t1, t2;
};
