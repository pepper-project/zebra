// vpiserver.c
// VPI module for verifier side of V-P interface
//   In our simulation model, V is a server and P
//   governs the flow of execution. This is for
//   compatibility with the software execution
//   model, and should not be taken as suggestive
//   of a real hardware architecture.
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

#include "vpiserver.h"

//
// register functions with Verilog simulator
//
extern cmt_io cmt_io_buf[];

void vpiserver_register(void) {
    s_cb_data cb_data_start =
        { .reason = cbStartOfSimulation
        , .cb_rtn = vpiserver_simstart
        , .obj = NULL
        , .time = NULL
        , .value = NULL
        , .user_data = NULL
        };
    vpi_register_cb(&cb_data_start);

    s_cb_data cb_data_end =
        { .reason = cbEndOfSimulation
        , .cb_rtn = vpiserver_simend
        , .obj = NULL
        , .time = NULL
        , .value = NULL
        , .user_data = NULL
        };
    vpi_register_cb(&cb_data_end);

    s_vpi_systf_data verifier_poll_data =
        { .type = vpiSysFunc
          , .sysfunctype = vpiIntFunc
          , .tfname = "$verifier_poll"
          , .calltf = verifier_poll_call
          , .compiletf = verifier_poll_comp
          , .sizetf = NULL
          , .user_data = NULL
        };
    vpi_register_systf(&verifier_poll_data);

    s_vpi_systf_data verifier_update_data =
        { .type = vpiSysTask
          , .sysfunctype = 0 //not a sysfunc.
          , .tfname = "$verifier_update"
          , .calltf = verifier_update_call
          , .compiletf = verifier_update_comp
          , .sizetf = NULL
          , .user_data = NULL
        };
    vpi_register_systf(&verifier_update_data);


}

//
// at start of simulation, get data structures set up
//
static PLI_INT32 vpiserver_simstart(s_cb_data *callback_data) {
    (void) callback_data;
    hwver_init = false;
    // initialize libcmtprecomp
    // first, get the PWS filename from the environment
    char *c_env = getenv("CMT_HWVER_PWS");
    if (c_env == NULL) {
        // not using hwver, no need to init
        return 0;
    } else {
        // make sure file exists!
        struct stat pws_stat;
        if (stat(c_env, &pws_stat) < 0) {
            perror("vpiserver_simstart: stat() on pws file");
            vpi_control(vpiFinish, 1);
            return 1;
        }
    }
    cmtprecomp_init(c_env);

    // initialize mpzs for send/rcv buffer
    for (unsigned i = 0; i < MPZ_BUF_LEN; i++) {
        mpz_init(mpz_buf[i]);
    }

    // listen on a UNIX socket
    if ( (listen_sock = socket(AF_UNIX, SOCK_STREAM | SOCK_NONBLOCK , 0)) < 0 ) {
        perror("vpiserver_simstart: opening stream socket");
        vpi_control(vpiFinish, 1);
        return 1;
    }

    // bind socket to path

    server.sun_family = AF_UNIX;
    getSocketPath(server.sun_path);
    unlink(server.sun_path);
    if ( bind(listen_sock, (struct sockaddr *) &server, sizeof(server)) ) {
        perror("vpiserver_simstart: binding stream socket");
        vpi_control(vpiFinish, 1);
        return 1;
    }

    listen(listen_sock, MAX_NUM_CONNECTIONS);
    pfds.fd = listen_sock;
    pfds.events = POLLIN;

    hwver_init = true;
    return 0;
}

//
// at end of simulation, clean up
//
static PLI_INT32 vpiserver_simend(s_cb_data *callback_data) {
    (void) callback_data;

    if (hwver_init) {
        // clean up UNIX socket
        socklen_t slen = sizeof(server);
        if (getsockname(listen_sock, (struct sockaddr *) &server, &slen) < 0) {
            perror("vpiserver_simend: getting UNIX socket name");
        }
        if (slen <= sizeof(server)) {
            unlink(server.sun_path);
        }
        close(listen_sock);

        // clean up mpz buffer
        for (unsigned i = 0; i < MPZ_BUF_LEN; i++) {
            mpz_clear(mpz_buf[i]);
        }

        // clean up various state
        cmtprecomp_deinit();

        hwver_init = false;
    }
    return 0;
}

//
// handle a prover's request for a new computation
//
static void new_comp(prover_request request) {
    unsigned comp_id = ((unsigned) request.id) % PIPELINE_DEPTH;

    // make sure that we're not colliding with a previously allocated computation
    if ( pc_data[comp_id].initialized ) {
        vpi_printf("new_comp: tried to reuse an in-use reqID\n");
        vpi_control(vpiFinish, 1);
        return;
    }

    // do the precomputations
    if ( cmtprecomp_new(&(pc_data[comp_id])) != 0 ) {
        perror("new_comp: cmtprecomp_new failed");
        vpi_control(vpiFinish, 1);
        return;
    }

    // set state-tracking variables
    pc_data[comp_id].cLayer = 0;
    pc_data[comp_id].cRound = 0;
    pc_data[comp_id].cPhase = SEND_INPUTS;
    init_cmt_io(comp_id, pc_data[comp_id].maxWidth, pc_data[comp_id].depth);
    generate_inputs(cmt_io_buf[comp_id].input, request.id);

}


static PLI_INT32 verifier_update_call(PLI_BYTE8 *user_data){
    (void) user_data;
    vpiHandle* arg_iter = get_arg_iter();
    int comp_id = get_int_arg(arg_iter);
    int cmt_data_type = get_int_arg(arg_iter);
    int layer = get_int_arg(arg_iter);
    int round = get_int_arg(arg_iter);
    free(arg_iter);

    switch (cmt_data_type) {
    case CMT_OUTPUT:
        if (pc_data[comp_id].cPhase != CHECK_OUTPUTS) {
            printf("ERROR: $verifier_update called with `CMT_OUTPUT for computation id %d at unexpected time\n", comp_id);
            vpi_control(vpiFinish, 1);
        }
        pc_data[comp_id].cPhase = SEND_Q0;
        break;
    case CMT_F012:
        if (pc_data[comp_id].cPhase != CHECK_F012 || (int) pc_data[comp_id].cLayer != layer || (int) pc_data[comp_id].cRound != round) {
            printf("ERROR: $verifier_update called with `CMT_F012 for computation id %d at unexpected time\n", comp_id);
            printf("expected round: %d\nrequested round: %d\nexpected layer: %d\nrequested layer %d\n",
                   pc_data[comp_id].cRound,
                   round,
                   pc_data[comp_id].cLayer,
                   layer);
            vpi_control(vpiFinish, 1);
        }
        pc_data[comp_id].cPhase = SEND_NEXT_R;
        break;
    case CMT_H:
        if (pc_data[comp_id].cPhase != CHECK_H || (int) pc_data[comp_id].cLayer != layer + 1) {
            printf("ERROR: $verifier_update called with `CMT_H for computation id %d at unexpected tiem\n", comp_id);
            printf("expected layer: %d\nrequested layer %d\n",
                   pc_data[comp_id].cLayer,
                   layer);
            vpi_control(vpiFinish, 1);
        }
        if (pc_data[comp_id].cLayer == pc_data[comp_id].depth) {
            printf("VERIFICATION FOR COMPUTATION %d COMPLETE!\n", comp_id);
            cmtprecomp_delete(&pc_data[comp_id]);
        }
        else {
            pc_data[comp_id].cPhase = SEND_NEXT_QI_OR_TAU;
        }
        break;
    default:
        printf("ERROR: $verifer_update called with result_type != CMT_{OUTPUT, F012, H}\n");
        vpi_control(vpiFinish, 1);
        break;

    }
    return 0;
}

static PLI_INT32 verifier_poll_call(PLI_BYTE8 *user_data) {
    (void) user_data;
    int pollRet = poll(&pfds, MAX_NUM_CONNECTIONS, TIMEOUT);
    if ( pollRet < 0) {
        perror("polling prover connection");
    }
    else  if (pollRet == 0) {
        printf("Timeout has expired.\n");
    }
    else {
        if(pfds.revents & POLLIN ){
            int rcv_socket = accept(listen_sock, NULL, NULL);
            FILE* readfp = fdopen(rcv_socket, "r");

            prover_request request = recieveHeader(readfp);
            handleReq(request, readfp, rcv_socket);

						close(rcv_socket);
            fclose(readfp);
        }
		}
    return 0;
}
static PLI_INT32 verifier_update_comp(PLI_BYTE8 *user_data) {
    (void) user_data;
    return 0;
}
static PLI_INT32 verifier_poll_comp(PLI_BYTE8 *user_data) {
    (void) user_data;
    return 0;
}

void handleReq(prover_request request, FILE* readfp, int write_socket) {
    (void) readfp;
    if (verifierSendsOn(request)) {

        switch (request.requestType) {
        case CMT_INPUT:
            //mux may be requested first, so might be initialized already.
            if (!pc_data[request.id % PIPELINE_DEPTH].initialized)
                new_comp(request);
            prepareInputs(request);
            break;
        case CMT_Q0:
            prepareQ0(request);
            break;
        case CMT_R:
            prepareR(request);
            break;
        case CMT_TAU:
            prepareT(request);
            break;
        case CMT_QI:
            printf("ERROR: prover requested Q_i\n");
            vpi_control(vpiFinish, 1);
            break;
        case CMT_MUXSEL:
            new_comp(request);
            break;
        }

        sendHeader(request, write_socket);

        if (request.requestType == CMT_MUXSEL) {
            bool* muxBits;
            int numMuxBits;
            cmtprecomp_getmuxbits(&muxBits, &numMuxBits);
            printf("numMuxBits: %d\n", numMuxBits);
            sendMuxBits(muxBits, numMuxBits, write_socket);
            free(muxBits);
        }
        else
            sendMPZ(request.howMany, write_socket);
    }

    else if (verifierRecievesOn(request)) {
        recieveMPZ(request.howMany, readfp);
        put_cmt_io(mpz_buf, request);
    }
    else {
        printf("ERROR: Invalid requestType in header\n");
        vpi_control(vpiFinish, 1);
    }

    returnValues(request);
}


void returnValues(prover_request request) {
    unsigned comp_id = ((unsigned) request.id) % PIPELINE_DEPTH;
    vpiHandle systf_handle = vpi_handle(vpiSysTfCall, NULL);
    s_vpi_value retval = {0,};
    retval.format = vpiIntVal;
    if (verifierSendsOn(request)) {
        retval.value.integer = 0; //nothing to do.
    }
    else {
        s_vpi_value argRetval = {0,};
        argRetval.format = vpiIntVal;
        vpiHandle arg_iter = vpi_iterate(vpiArgument, systf_handle);

        vpiHandle arg_handle = vpi_scan(arg_iter);
        argRetval.value.integer = comp_id;
        vpi_put_value(arg_handle, &argRetval, NULL, vpiNoDelay);

        arg_handle = vpi_scan(arg_iter);
        argRetval.value.integer = request.requestType;
        vpi_put_value(arg_handle, &argRetval, NULL, vpiNoDelay);

        arg_handle = vpi_scan(arg_iter);
        argRetval.value.integer = request.layer;
        vpi_put_value(arg_handle, &argRetval, NULL, vpiNoDelay);

        arg_handle = vpi_scan(arg_iter);
        argRetval.value.integer = request.round;
        vpi_put_value(arg_handle, &argRetval, NULL, vpiNoDelay);

        arg_handle = vpi_scan(arg_iter);
        argRetval.format = vpiVectorVal;

        vpiHandle element_handle;
        switch (request.requestType) {
        case CMT_OUTPUT:
            for (unsigned i = 0; i < pc_data[comp_id].oSize; i++) {
                element_handle = vpi_handle_by_index(arg_handle, i);
                argRetval.value.vector = to_vector_val(cmt_io_buf[comp_id].output[i]);
                vpi_put_value(element_handle, &argRetval, NULL, vpiNoDelay);
            }
            arg_handle = vpi_scan(arg_iter);
            for (unsigned i = 0; i < pc_data[comp_id].oSize; i++) {
                element_handle = vpi_handle_by_index(arg_handle, i);
                argRetval.value.vector = to_vector_val(pc_data[comp_id].chi_o[i]);
                vpi_put_value(element_handle, &argRetval, NULL, vpiNoDelay);
            }
            retval.value.integer = 1;
            break;
        case CMT_F012:
            for (unsigned i = 0; i < 3; i++) {
                element_handle = vpi_handle_by_index(arg_handle, i);
                argRetval.value.vector = to_vector_val(cmt_io_buf[comp_id].layer_io[request.layer].F012[request.round][i]);
                vpi_put_value(element_handle, &argRetval, NULL, vpiNoDelay);
            }
            arg_handle = vpi_scan(arg_iter);
            for (unsigned i = 0; i < 3; i++) {
                element_handle = vpi_handle_by_index(arg_handle, i);
                argRetval.value.vector = to_vector_val(pc_data[comp_id].layers[request.layer].f_wt[3 * request.round + i]);
                vpi_put_value(element_handle, &argRetval, NULL, vpiNoDelay);
            }
            retval.value.integer = 2;
            break;
        case CMT_H:
            for (unsigned i = 0; i < pc_data[comp_id].layers[request.layer].hSize; i++) {
                element_handle = vpi_handle_by_index(arg_handle, i);
                argRetval.value.vector = to_vector_val(cmt_io_buf[comp_id].layer_io[request.layer].H[i]);
                vpi_put_value(element_handle, &argRetval, NULL, vpiNoDelay);
            }
            arg_handle = vpi_scan(arg_iter);
            for (unsigned i = 0; i < pc_data[comp_id].layers[request.layer].hSize; i++) {
                element_handle = vpi_handle_by_index(arg_handle, i);
                argRetval.value.vector = to_vector_val(pc_data[comp_id].layers[request.layer].h_wt[i]);
                vpi_put_value(element_handle, &argRetval, NULL, vpiNoDelay);
            }
            unsigned offset = pc_data[comp_id].layers[request.layer].hSize;
            element_handle = vpi_handle_by_index(arg_handle, offset);
            argRetval.value.vector = to_vector_val(pc_data[comp_id].layers[request.layer].add);

            element_handle = vpi_handle_by_index(arg_handle, offset + 1);
            argRetval.value.vector = to_vector_val(pc_data[comp_id].layers[request.layer].mul);

            element_handle = vpi_handle_by_index(arg_handle, offset + 2);
            argRetval.value.vector = to_vector_val(pc_data[comp_id].layers[request.layer].sub);

            element_handle = vpi_handle_by_index(arg_handle, offset + 3);
            argRetval.value.vector = to_vector_val(pc_data[comp_id].layers[request.layer].muxl);

            element_handle = vpi_handle_by_index(arg_handle, offset + 4);
            argRetval.value.vector = to_vector_val(pc_data[comp_id].layers[request.layer].muxr);

            retval.value.integer = 3;
            break;
        }
    }
    vpi_put_value(systf_handle, &retval, NULL, vpiNoDelay);

}

void prepareInputs(prover_request request) {
    unsigned comp_id = ((unsigned) request.id) % PIPELINE_DEPTH;
    if (pc_data[comp_id].cPhase != SEND_INPUTS) {
        printf("ERROR: Prover requested inputs at unexpected time.\n");
        vpi_control(vpiFinish, 1);
    }
    else {
        for (int i = 0; i < request.howMany; i++) {
            mpz_set(mpz_buf[i], cmt_io_buf[comp_id].input[i]);
        }
        pc_data[comp_id].cPhase = CHECK_OUTPUTS;
    }
}
void prepareQ0(prover_request request) {
    unsigned comp_id = ((unsigned) request.id) % PIPELINE_DEPTH;
    if (pc_data[comp_id].cPhase != SEND_Q0) {
        printf("ERROR: prover requested q0 at unexpected time.\n");
        vpi_control(vpiFinish, 1);
    }
    else {
        for (int i = 0; i < request.howMany; i++) {
            mpz_set(mpz_buf[i], pc_data[comp_id].q0[i]);
        }
        put_cmt_io(mpz_buf, request);
        pc_data[comp_id].cPhase = CHECK_F012;
    }
}
void prepareR(prover_request request) {
    unsigned comp_id = ((unsigned) request.id) % PIPELINE_DEPTH;
    if (pc_data[comp_id].cPhase != SEND_NEXT_R) {
        printf("ERROR: prover requested r at unexpected time.\n");
        vpi_control(vpiFinish, 1);
    }
    else {
        mpz_set(mpz_buf[0], pc_data[comp_id].layers[request.layer].r[request.round]);
        put_cmt_io(mpz_buf, request);
        //       printf(" pc_data[comp_id].layers[pc_data[comp_id].cLayer + 1].bSize: %d",  pc_data[comp_id].layers[pc_data[comp_id].cLayer].bSize);
        if (pc_data[comp_id].cRound < 2 * pc_data[comp_id].layers[pc_data[comp_id].cLayer].bSize  - 1) {
            pc_data[comp_id].cRound++;
            pc_data[comp_id].cPhase = CHECK_F012;
        }
        else {
            pc_data[comp_id].cRound = 0;
            pc_data[comp_id].cLayer++;
            pc_data[comp_id].cPhase = CHECK_H;
        }
    }
}
void prepareT(prover_request request) {
    unsigned comp_id = ((unsigned) request.id) % PIPELINE_DEPTH;
    if (pc_data[comp_id].cPhase != SEND_NEXT_QI_OR_TAU) {
        printf("ERROR: prover requested tau at unexpected time.\n");
        vpi_control(vpiFinish, 1);
    }
    else {
        mpz_set(mpz_buf[0], pc_data[comp_id].layers[request.layer].tau);
        pc_data[comp_id].cPhase = CHECK_F012;
    }
}
