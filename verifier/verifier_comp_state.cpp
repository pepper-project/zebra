#include "verifier_comp_state.h"

#include <iostream>
#include <circuit/cmtgkr_env.h>

#define MASK 0x1FFFFFFFFFFFFFFFULL

using namespace std;

extern cmt_io cmt_io_buf[];
extern mpz_t mpz_buf[];
extern int netBytesSent;
extern int netBytesRecieved;

void VerifierCompState::init(VerifierPrecomputation* precomp, int comp_state_id) {
    this->precomp = precomp;
    this->comp_state_id = comp_state_id;
    phase = SEND_INPUTS;
    successful = true;
    mpz_init(a);
    mpz_init(e);

#ifdef USE_MPFQ
    mpfq_p_25519_field_init(theField);
    mpfq_p_25519_init(theField, &mpfq_e);
    mpfq_p_25519_init(theField, &mpfq_a);
    mpfq_p_25519_init(theField, &mpfq_tmp);
#endif

    m_sumcheck_modcmp = new double[precomp->depth - 1];
    m_sumcheck_extrap = new double[precomp->depth - 1];
    m_sumcheck_final = new double[precomp->depth - 1];
    for (int i = 0; i < precomp->depth - 1; i++) {
        m_sumcheck_modcmp[i] = 0;
        m_sumcheck_extrap[i] = 0;
        m_sumcheck_final[i] = 0;
    }
    m_setup = 0, m_mlext_input = 0, m_mlext_output = 0;
}

//check the request is valid, etc.
//then retrieve from cmt_io_buf.
//do whatever computation is nessescary:
//checkoutputs: compute and set a,e = mlext of evalutor at q0

void VerifierCompState::checkOutputs(prover_request request) {

    //check valid request, phase, etc.
    int outputSize = precomp->layerSizes[0];
       //    cout << "Phase: " << phase << endl;
    if (phase != CHECK_OUTPUTS || request.howMany != outputSize) {
        cout << "ERROR: prover sent outputs at unexpected time, or wrong # of outputs. exiting. " << endl;
        exit(1);
    }

    //copy in the purported outputs
    outputs.resize(outputSize);

#ifdef USE_MPFQ
    mpfq_p_25519_elt* mpfq_outputs= new mpfq_p_25519_elt[outputSize];
    mpfq_p_25519_elt* mpfq_chis = new mpfq_p_25519_elt[outputSize];
#endif

    for (int i = 0; i < outputSize; i++) {
        mpz_set(outputs[i], cmt_io_buf[comp_state_id].output[i]);
    }

    //compute a0 = V_0(q0), the m.lext. of the evaluator poly. of the outputs.
    MPZVector chis(outputSize);

    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t1);

    for (int _i = 0; _i < NREPS; _i++) {
        computeChiAll(chis, precomp->qi[0], precomp->subcircuit->prime);
    }

    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t2);
    m_setup +=( (t2.tv_sec - t1.tv_sec) * BILLION  + t2.tv_nsec - t1.tv_nsec ) / (double) NREPS;

#ifdef USE_MPFQ
    for (int i = 0; i < outputSize; i++) {
        mpfq_p_25519_init(theField, &mpfq_outputs[i]);
        mpfq_p_25519_init(theField, &mpfq_chis[i]);
        mpfq_p_25519_set_mpz(theField, mpfq_outputs[i], outputs[i]);
        mpfq_p_25519_set_mpz(theField, mpfq_chis[i], chis[i]);
    }
#endif

    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t1);
    for (int _i = 0; _i < NREPS; _i++) {
#ifdef USE_MPFQ
        mpfq_p_25519_set_ui(theField, mpfq_a, 0);
        for (int i = 0; i < outputSize; i++) {
            mpfq_p_25519_mul(theField, mpfq_tmp, mpfq_outputs[i], mpfq_chis[i]);
            mpfq_p_25519_add(theField, mpfq_a, mpfq_a, mpfq_tmp);
        }
#else
        mpz_set_ui(a, 0);
        for (int i = 0; i < outputSize; i++) {
            mpz_addmul(a, outputs[i], chis[i]);
        }
        mpz_mod(a, a, precomp->subcircuit->prime);
#endif
    }
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t2);
    m_mlext_output =( (t2.tv_sec - t1.tv_sec) * BILLION  + t2.tv_nsec - t1.tv_nsec ) / (double) NREPS;


#ifdef USE_MPFQ
    mpfq_p_25519_set(theField, mpfq_e, mpfq_a);
#else
    mpz_set(e, a);
#endif


#ifdef USE_MPFQ
    for (int i = 0; i < outputSize; i++) {
        mpfq_p_25519_clear(theField, &mpfq_outputs[i]);
        mpfq_p_25519_clear(theField, &mpfq_chis[i]);
    }
    free(mpfq_outputs);
    free(mpfq_chis);
#endif

    //ready to start sumcheck protocol.
    phase = SEND_Q0;


}

//check update e, state.
void VerifierCompState::checkF012(prover_request request) {
    if (phase != CHECK_F012 || request.round != currRound || request.layer != currLayer) {
        cout << "ERROR: prover sent sumcheck round response at unexpected time. " << endl;
        cout << "requested/curr round: " << request.round << "/" << currRound << endl;
        cout << "requested/curr layer: " << request.layer << "/" << currLayer << endl;
        cout << "phase/expected phase: " << phaseToStr(phase) << "/" << phaseToStr(CHECK_F012) << endl;

        exit(1);
    }

    //copy in prover's output
    MPZVector F012(3);
#ifdef USE_MPFQ
    mpfq_p_25519_elt mpfq_f012[3];
#endif
    for (int i = 0; i < 3; i++) {
        mpz_set(F012[i], cmt_io_buf[comp_state_id].layer_io[request.layer].F012[request.round][i]);
#ifdef USE_MPFQ
        mpfq_p_25519_init(theField, &mpfq_f012[i]);
        mpfq_p_25519_set_mpz(theField, mpfq_f012[i], F012[i]);
#endif
    }

    //check e == F[0] + F[1]
    mpz_t prime;
    mpz_init_set(prime, precomp->subcircuit->prime);

    mpz_t e0, tmp;
    mpz_init(e0);
    mpz_init(tmp);



    bool err = false;

    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t1);
    for (int _i = 0; _i < NREPS; _i++) {
#ifndef USE_MPFQ
        mpz_add(tmp, F012[0], F012[1]);
        mpz_sub(e0, e, tmp);
        if ( !mpz_divisible_p(e0, prime) ) {
            err = true;
        }
#else
        mpfq_p_25519_add(theField, mpfq_tmp, mpfq_f012[0], mpfq_f012[1]);
        if ( mpfq_p_25519_cmp(theField, mpfq_e, mpfq_tmp) ) {
            err = true;
        }
#endif //USE_MPFQ
    }
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t2);
    m_sumcheck_modcmp[currLayer] += ( (t2.tv_sec - t1.tv_sec) * BILLION  + t2.tv_nsec - t1.tv_nsec ) / (double) NREPS;

    if (err) {
        cout << "ERROR: F[0] + F[1] != e" << endl;
#ifdef USE_MPFQ
        cout << "Expected: ";
        mpfq_p_25519_print(theField, mpfq_e);
        cout << " but got ";
        mpfq_p_25519_print(theField, mpfq_tmp);
        cout << endl;
#else
        char *e_str = mpz_get_str(NULL, 16, e0);
        char *tmp_str = mpz_get_str(NULL, 16, tmp);
        cout << "Expected 0x" << e_str << " but got 0x" << tmp_str << endl;
        free(e_str);
        free(tmp_str);
#endif
        cout << "current layer: " << currLayer << endl;
        cout << "current round: " << currRound << endl;
        successful = false;
    }

    mpz_t rj;
    mpz_init(rj);
    mpz_set(rj, precomp->ri[currLayer][currRound]);

#ifndef USE_FJM1
    //now compute F012(rj)
    MPZVector weights(3);
#ifdef USE_MPFQ
    mpfq_p_25519_elt mpfq_weights[3];
#endif

    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t1);
    for (int _i = 0; _i < NREPS; _i++) {
        bary_precompute_weights3(weights, rj, precomp->subcircuit->prime);
    }
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t2);
    m_setup += ( (t2.tv_sec - t1.tv_sec) * BILLION  + t2.tv_nsec - t1.tv_nsec ) / (double) NREPS;

#ifdef USE_MPFQ
    for (int i = 0; i < 3; i++) {
        mpfq_p_25519_init(theField, &mpfq_weights[i]);
        mpfq_p_25519_set_mpz(theField, mpfq_weights[i], weights[i]);
    }
#endif

    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t1);



    for (int _i = 0; _i < NREPS; _i++) {
#ifndef USE_MPFQ
        mpz_mul(e, F012[0], weights[0]);
        mpz_addmul(e, F012[1], weights[1]);
        mpz_addmul(e, F012[2], weights[2]);
#else
        mpfq_p_25519_mul(theField, mpfq_e, mpfq_f012[0], mpfq_weights[0]);
        mpfq_p_25519_mul(theField, mpfq_tmp, mpfq_f012[1], mpfq_weights[1]);
        mpfq_p_25519_add(theField, mpfq_e, mpfq_e, mpfq_tmp);
        mpfq_p_25519_mul(theField, mpfq_tmp, mpfq_f012[2], mpfq_weights[2]);
        mpfq_p_25519_add(theField, mpfq_e, mpfq_e, mpfq_tmp);
#endif
    }
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t2);
    m_sumcheck_extrap[currLayer] += ( (t2.tv_sec - t1.tv_sec) * BILLION  + t2.tv_nsec - t1.tv_nsec ) / (double) NREPS;

#else
    // quick and dirty way of computing e from fj(-1), fj(0), and fj(1)
    // this should be optimized as possible.
    // Also right now "half" assumes that p = 2^61 - 1 !

    mpz_t c1, c2, half, rj_squared;
    mpz_init(c1);
    mpz_init(c2);
    mpz_init(rj_squared);

    // 2^-1 = (p + 1) / 2 (mod p)
    mpz_init_set(half, precomp->subcircuit->prime);
    mpz_add_ui(half, half, 1);
    mpz_divexact_ui(half, half, 2);

    // compute c2

    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t1);
    for (int _i = 0; _i < NREPS; _i++) {
        mpz_add(c2, F012[2], F012[1]);
        mpz_mul(c2, c2, half);
        mpz_sub(c2, c2, F012[0]);
        mpz_mod(c2, c2, precomp->subcircuit->prime);

        // compute c1
        mpz_sub(c1, F012[1], F012[2]);
        mpz_mul(c1, c1, half);
        mpz_mod(c1, c1, precomp->subcircuit->prime);

        // compute f_j(rj)
        mpz_set(e, F012[0]);
        mpz_addmul(e, c1, rj);
        mpz_mul(rj_squared, rj, rj);
        mpz_addmul(e, c2, rj_squared);
        mpz_mod(e, e, precomp->subcircuit->prime);
    }
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t2);
    m_sumcheck_extrap[currLayer] += ( (t2.tv_sec - t1.tv_sec) * BILLION  + t2.tv_nsec - t1.tv_nsec ) / (double) NREPS;

    mpz_clear(half);
    mpz_clear(c1);
    mpz_clear(c2);
    mpz_clear(rj_squared);
#endif

    mpz_clear(rj);

#ifdef USE_MPFQ
    for (int i = 0; i < 3; i++) {
        mpfq_p_25519_clear(theField, &mpfq_f012[i]);
        mpfq_p_25519_clear(theField, &mpfq_weights[i]);
    }
#endif

    //OK sending the next random el.
    phase = SEND_NEXT_R;
}

void VerifierCompState::checkH(prover_request request) {
    //note: This check happens at the end of the sumcheck protocol,
    //after currLayer has already been incremented.  But the number of
    //H coefficients is supposed to be equal to log(numINPUTS) to the
    //layer.
    int numHcoeffs = precomp->logLayerSizes[currLayer] + 1;
    if (phase != CHECK_H || request.howMany != numHcoeffs) {
        cout << "ERROR: prover sent H poly. at unexpected time, or wrong # of coefficients." << endl;
        exit(1);
    }

    //copy in prover's output
    MPZVector H(numHcoeffs);
#ifdef USE_MPFQ
    mpfq_p_25519_elt * mpfq_H = new mpfq_p_25519_elt[numHcoeffs];
#endif
    for (int i = 0; i < numHcoeffs; i++) {
        mpz_set(H[i], cmt_io_buf[comp_state_id].layer_io[request.layer].H[i]);
#ifdef USE_MPFQ
        mpfq_p_25519_init(theField, &mpfq_H[i]);
        mpfq_p_25519_set_mpz(theField, mpfq_H[i], H[i]);
#endif
    }

    //compute next layer's a, assuming V(w1) = v1 = H[0], V(w2) = v2 = H[1].
    mpz_t v1, v2;
    mpz_init_set(v1, H[0]);
    mpz_init_set(v2, H[1]);

    mpz_t tmp1, tmp2, tmp3;
    mpz_init(tmp1);
    mpz_init(tmp2);
    mpz_init(tmp3);

    //minus 1 because of note above.

#ifdef USE_MPFQ
    mpfq_p_25519_elt mpfq_v1, mpfq_v2, mpfq_mul, mpfq_add, mpfq_sub, mpfq_muxl, mpfq_muxr;
    mpfq_p_25519_init(theField, &mpfq_v1); mpfq_p_25519_set_mpz(theField, mpfq_v1, v1);
    mpfq_p_25519_init(theField, &mpfq_v2); mpfq_p_25519_set_mpz(theField, mpfq_v2, v2);
    mpfq_p_25519_init(theField, &mpfq_mul); mpfq_p_25519_set_mpz(theField, mpfq_mul, precomp->mul[currLayer-1]);
    mpfq_p_25519_init(theField, &mpfq_add); mpfq_p_25519_set_mpz(theField, mpfq_add, precomp->add[currLayer-1]);
    mpfq_p_25519_init(theField, &mpfq_sub); mpfq_p_25519_set_mpz(theField, mpfq_sub, precomp->sub[currLayer-1]);
    mpfq_p_25519_init(theField, &mpfq_muxl); mpfq_p_25519_set_mpz(theField, mpfq_muxl, precomp->muxl[currLayer-1]);
    mpfq_p_25519_init(theField, &mpfq_muxr); mpfq_p_25519_set_mpz(theField, mpfq_muxr, precomp->muxr[currLayer-1]);
#endif

    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t1);

    bool err = false;
    for (int _i = 0; _i < NREPS; _i++) {
#ifdef USE_MPFQ
        mpfq_p_25519_add(theField, mpfq_a, mpfq_v1, mpfq_v2);
        mpfq_p_25519_mul(theField, mpfq_a, mpfq_a, mpfq_add);

        mpfq_p_25519_mul(theField, mpfq_tmp, mpfq_v1, mpfq_v2);
        mpfq_p_25519_mul(theField, mpfq_tmp, mpfq_tmp, mpfq_mul);

        mpfq_p_25519_add(theField, mpfq_a, mpfq_a, mpfq_tmp);

        mpfq_p_25519_sub(theField, mpfq_tmp, mpfq_v1, mpfq_v2);
        mpfq_p_25519_mul(theField, mpfq_tmp, mpfq_tmp, mpfq_sub);

        mpfq_p_25519_add(theField, mpfq_a, mpfq_a, mpfq_tmp);

        mpfq_p_25519_mul(theField, mpfq_tmp, mpfq_v1, mpfq_muxl);
        mpfq_p_25519_add(theField, mpfq_a, mpfq_a, mpfq_tmp);

        mpfq_p_25519_mul(theField, mpfq_tmp, mpfq_v2, mpfq_muxr);
        mpfq_p_25519_add(theField, mpfq_a, mpfq_a, mpfq_tmp);

        if (mpfq_p_25519_cmp(theField, mpfq_a, mpfq_e)) {
            err = true;
        }
#else
        mpz_add(a, v1, v2);
        mpz_mul(a, a, precomp->add[currLayer - 1]);

        mpz_mul(tmp1, v1, v2);
        mpz_addmul(a, tmp1, precomp->mul[currLayer -1]);

        mpz_sub(tmp1, v1, v2);
        mpz_addmul(a, tmp1, precomp->sub[currLayer - 1]);

        mpz_addmul(a, v1, precomp->muxl[currLayer - 1]);
        mpz_addmul(a, v2, precomp->muxr[currLayer - 1]);

        mpz_sub(a, a, e);

        if ( !mpz_divisible_p(a, precomp->subcircuit->prime) ) {
            err = true;
        }

#endif //USE_MPFQ
    }
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t2);
    m_sumcheck_final[currLayer - 1] +=  ( (t2.tv_sec - t1.tv_sec) * BILLION  + t2.tv_nsec - t1.tv_nsec ) / (double) NREPS;

    if (err) {
        cout << "ERROR: a' != e at final round of sumcheck, layer " << currLayer - 1 << endl;
        char *e_str = mpz_get_str(NULL, 16, e);
        char *a_str = mpz_get_str(NULL, 16, a);
        cout << "Expected 0x" << e_str << " but got 0x" << a_str << endl;
        successful = false;
        free(e_str);
        free(a_str);
    }

    //now compute a_next = H(tau) from the coefficients
    mpz_t tau;
    mpz_init_set(tau, precomp->tau[currLayer - 1]);

    MPZVector weights(numHcoeffs);

#ifdef USE_MPFQ
    mpfq_p_25519_elt * mpfq_weights = new mpfq_p_25519_elt[numHcoeffs];
#endif

    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t1);
    for (int _i = 0; _i < NREPS; _i++) {
        bary_precompute_weights(weights, tau, precomp->subcircuit->prime);
    }
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t2);
    m_setup += ( (t2.tv_sec - t1.tv_sec) * BILLION  + t2.tv_nsec - t1.tv_nsec ) / (double) NREPS;

#ifdef USE_MPFQ
    for (int i = 0; i < numHcoeffs; i++) {
        mpfq_p_25519_init(theField, &mpfq_weights[i]);
        mpfq_p_25519_set_mpz(theField, mpfq_weights[i], weights[i]);
    }
#endif

    MPZVector avec(1);

    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t1);
#ifdef USE_MPFQ
    for (int _i = 0; _i < NREPS; _i++) {
        mpfq_p_25519_set_ui(theField, mpfq_a, 0);
        for (int i = 0; i < numHcoeffs; i++) {
            mpfq_p_25519_mul(theField, mpfq_tmp, mpfq_H[i], mpfq_weights[i]);
            mpfq_p_25519_add(theField, mpfq_a, mpfq_a, mpfq_tmp);
        }
    }
#else
    for (int _i = 0; _i < NREPS; _i++) {
        bary_extrap(avec, H, weights, precomp->subcircuit->prime);
    }
#endif
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t2);

    m_sumcheck_final[currLayer - 1] += ( (t2.tv_sec - t1.tv_sec) * BILLION  + t2.tv_nsec - t1.tv_nsec )/ (double) NREPS;

#ifdef USE_MPFQ
    mpfq_p_25519_set(theField, mpfq_e, mpfq_a);
#else
    mpz_set(a, avec[0]);
    mpz_set(e, a);
#endif

#ifdef USE_MPFQ
    for (int i = 0; i < numHcoeffs; i++) {
        mpfq_p_25519_clear(theField, &mpfq_H[i]);
        mpfq_p_25519_clear(theField, &mpfq_weights[i]);
    }
    free(mpfq_H);
    free(mpfq_weights);
#endif

    mpz_clear(v1), mpz_clear(v2), mpz_clear(tmp1), mpz_clear(tmp2), mpz_clear(tmp3);
    if (currLayer == (precomp->depth) - 1 ) {
        doFinalCheck();
    }

    else {
        phase = SEND_NEXT_QI_OR_TAU;
    }


}

//check that a_d  = Vd(qd), i.e. compute the mlext. of the inputs at the last q.
void VerifierCompState::doFinalCheck() {
    int inputLayerSize = precomp->layerSizes[precomp->depth - 1];
    MPZVector chis(inputLayerSize);
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t1);
    for (int _i = 0; _i < NREPS; _i++) {
        computeChiAll(chis, precomp->qi[precomp->depth - 1], precomp->subcircuit->prime);
    }
    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t2);
    m_setup += ( (t2.tv_sec - t1.tv_sec) * BILLION  + t2.tv_nsec - t1.tv_nsec ) / (double) NREPS;

#ifdef USE_MPFQ
    mpfq_p_25519_elt* mpfq_inputs= new mpfq_p_25519_elt[inputLayerSize];
    mpfq_p_25519_elt* mpfq_chis = new mpfq_p_25519_elt[inputLayerSize];

    for (int i = 0; i < inputLayerSize; i++) {
        mpfq_p_25519_init(theField, &mpfq_inputs[i]);
        mpfq_p_25519_init(theField, &mpfq_chis[i]);
        mpfq_p_25519_set_mpz(theField, mpfq_inputs[i], inputs[i]);
        mpfq_p_25519_set_mpz(theField, mpfq_chis[i], chis[i]);
    }
#endif


    mpz_t ans;
    mpz_init_set_ui(ans, 0);

#ifdef USE_MPFQ
    mpfq_p_25519_elt mpfq_ans;
    mpfq_p_25519_init(theField, &mpfq_ans);
#endif

    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t1);

    bool err = false;
    for (int _i = 0; _i < NREPS; _i++) {
#ifdef USE_MPFQ
        mpfq_p_25519_set_ui(theField, mpfq_ans, 0);
        for (int i = 0; i < inputLayerSize; i++) {
            mpfq_p_25519_mul(theField, mpfq_tmp, mpfq_inputs[i], mpfq_chis[i]);
            mpfq_p_25519_add(theField, mpfq_ans, mpfq_ans, mpfq_tmp);
        }

        if (mpfq_p_25519_cmp(theField, mpfq_ans, mpfq_a) != 0) {
            err = true;
        }
#else
        mpz_set_ui(ans, 0);
        for (int i = 0; i < inputLayerSize; i++) {
            mpz_addmul(ans, inputs[i], chis[i]);
        }
        mpz_mod(ans, ans, precomp->subcircuit->prime);

        if (mpz_cmp(ans, a) != 0) {
            err = true;
        }
#endif
    }

    clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t2);
    m_mlext_input = ( (t2.tv_sec - t1.tv_sec) * BILLION  + t2.tv_nsec - t1.tv_nsec ) / (double) NREPS;

    if (err) {
        cout << "ERROR: Final check (m.l. ext. of inputs) failed: a_d != Vd(qd). " << endl;
        char *e_str = mpz_get_str(NULL, 16, ans);
        char *a_str = mpz_get_str(NULL, 16, a);
        cout << "Expected 0x" << e_str << " but got 0x" << a_str << endl;
        successful = false;
        free(e_str);
        free(a_str);
    }

#ifdef USE_MPFQ
    for (int i = 0; i < inputLayerSize; i++) {
        mpfq_p_25519_clear(theField, &mpfq_inputs[i]);
        mpfq_p_25519_clear(theField, &mpfq_chis[i]);
    }
    free(mpfq_inputs);
    free(mpfq_chis);
#endif

    if (successful)
        cout << endl << endl << "**VERIFICATION SUCCESSFUL [" << comp_state_id << "] **" << endl;
    else
        cout << "**VERIFICATION FAILED [" << comp_state_id << "] **" << endl;

    mpz_clear(ans);

    printStats();


}





//these functions just check the prover's request is valid and then
//copy the proper mpz's into mpz_buf.

//check request.howMany = totalnuminputs, it's the right phase, etc.
//generate the inputs and put them in the mpz_buf.
void VerifierCompState::generateInputs(prover_request request) {
    int inputSize = precomp->layerSizes[precomp->depth - 1];
    inputs.resize(precomp->layerSizes[precomp->depth - 1]);
    if (phase != SEND_INPUTS || request.howMany != inputSize) {
        cout << "prover requested inputs at unexpected time, or wrong # of inputs. exiting." << endl;
        exit(1);
    }
#ifdef DEBUG
    cout << "generating inputs for computation id: " << request.id << endl;
#endif

    mpz_t tmp;
    mpz_init(tmp);

    //getInputSize returns the number of non-constant inputs to the
    //computation
    MPQVector vec(precomp->subcircuit->getInputSize());
    for (size_t j = 0; j < vec.size(); j++)
        mpq_set_ui(vec[j],  (10 + request.id) * (j + 1), 1);

    //set the inputs to the computation, including the constants
    precomp->subcircuit->initializeInputs(vec);

    //now get the input layer and extract the full input, including
    //constants.
    CircuitLayer& inLayer = precomp->subcircuit->getInputLayer();

    for (int j = 0; j < inLayer.size(); j++) {
        inLayer.gate(j).getValue(tmp);
        mpz_set(inputs[j], tmp);
        mpz_set(mpz_buf[j], tmp);
    }

    mpz_clear(tmp);
    phase = CHECK_OUTPUTS;

}

//again, just check it's the right phase and #, etc., and put it in the buf.
void VerifierCompState::sendQ0(prover_request request) {
    if (phase != SEND_Q0 || request.howMany != (int) precomp->qi[0].size()) {
        cout << "prover requested q0 at unexpected time, or wrong size specified for q0. exiting. " << endl;
        exit(1);
    }
    for (int i = 0; i < request.howMany; i++) {
        mpz_set(mpz_buf[i], precomp->qi[0][i]);
    }
    phase = CHECK_F012;
    currRound = 0;
    currLayer = 0;
}

void VerifierCompState::sendNextR(prover_request request) {
    if (phase != SEND_NEXT_R || request.howMany != 1 || request.round != currRound || request.layer != currLayer) {
        cout << "ERROR: prover requested sumcheck random el. at wrong time" << endl;
        exit(1);
    }

    mpz_set(mpz_buf[0], precomp->ri[currLayer][currRound]);

    int inputLayerSize = precomp->logLayerSizes[currLayer + 1];

    if (currRound < 2* inputLayerSize  - 1) {
        currRound++;
        phase = CHECK_F012;
    }
    else {
        currRound = 0;
        currLayer++;
        phase = CHECK_H;
    }

}
void VerifierCompState::sendNextT(prover_request request) {
    if (phase != SEND_NEXT_QI_OR_TAU || request.howMany != 1 || request.layer != currLayer) {
        cout << "ERROR: Tau requested at wrong time" << endl;
        exit(1);
    }

    mpz_set(mpz_buf[0], precomp->tau[currLayer - 1]);
    phase = CHECK_F012;
}
void VerifierCompState::sendNextQI(prover_request request) {
    if (phase != SEND_NEXT_QI_OR_TAU || request.howMany != (int) precomp->qi[currLayer].size() || request.layer != currLayer) {
        cout << "ERROR: q_i requested at wrong time" << endl;
        exit(1);
    }

    for (int i = 0; i < request.howMany; i++) {
        mpz_set(mpz_buf[i], precomp->qi[currLayer][i]);
    }

    phase = CHECK_F012;
}



void VerifierCompState::printStats() {
    cout << "RUNTIMES (microseconds)" << endl;

    cout << "    m.l. ext. of outputs: " << m_mlext_output/(double) 1000.0 << endl;
    cout << "    m.l. ext. of inputs: " << m_mlext_input/(double) 1000.0 << endl;

    double total = m_mlext_input + m_mlext_output;

    for (int i = 0; i < precomp->depth - 1; i++) {
        cout << "    sumcheck layer " << i << " (mod/compare, extrap, final): ";
        cout << m_sumcheck_modcmp[i]/(double) 1000.0<< ", ";
        cout << m_sumcheck_extrap[i]/(double) 1000.0<< ", ";
        cout << m_sumcheck_final[i]/(double) 1000.0<< ", " << endl;
        total += m_sumcheck_modcmp[i] + m_sumcheck_extrap[i] + m_sumcheck_final[i];
    }

    cout << "    total time for online checks " << total/(double) 1000.0 << endl;

    //note: most setup is done in verifier_precomp, but some functions
    //which only depend on V's randomness (bary_precompute_weights(),
    //computeChiall() ), are called in verifier_comp_state.

    cout << "    setup time: " << (m_setup +  precomp->m_setup)/(double) 1000.0 << endl;


    cout << "    total bytes sent: " << netBytesSent << endl;
    cout << "    total bytes received " << netBytesRecieved << endl << endl;

}
