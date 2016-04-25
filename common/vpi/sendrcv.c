
#include "sendrcv.h"
#include "sendrcv_typechecker.h"
extern mpz_t mpz_buf[];
static bool muxBitsBuf[10000];
//
// Register $send and $recieve with the Verilog simulator.
//
void sendrcv_register(void) {

    /* ** NOTE for Icarus Verilog **
     *
     * When compiling system functions, Icarus ignores the
     * sizetf field of s_vpi_systf_data. Instead, you must
     * create an .sft file and provide it alongside the .v
     * file when compiling the latter into a .vvp file.
     *
     * For example, the .sft file corresponding to $f_add
     * and $f_mul looks like this:

     $f_add vpiSysFuncSized 61 unsigned
     $f_mul vpiSysFuncSized 61 unsigned

     * and you should invoke iverilog like so:

     iverilog -oarith.vvp arith.v arith.sft

    */

    s_vpi_systf_data cmt_init_data =
        { .type = vpiSysFunc
          , .sysfunctype = vpiIntFunc
          , .tfname = "$cmt_init"
          , .calltf = cmt_init_call
          , .compiletf = cmt_init_comp
          , .sizetf = cmt_init_size
          , .user_data = NULL
        };
    vpi_register_systf(&cmt_init_data);

    s_vpi_systf_data cmt_request_data =
        { .type = vpiSysTask
          , .sysfunctype = 0 //not a sysfunc.
          , .tfname = "$cmt_request"
          , .calltf = cmt_request_call
          , .compiletf = cmt_request_comp
          , .sizetf = NULL
          , .user_data = NULL
        };
    vpi_register_systf(&cmt_request_data);

    s_vpi_systf_data cmt_send_data =
        { .type = vpiSysTask
          , .sysfunctype = 0 //not a sysfunc.
          , .tfname = "$cmt_send"
          , .calltf = cmt_send_call
          , .compiletf = cmt_send_comp
          , .sizetf = NULL
          , .user_data = NULL
        };
    vpi_register_systf(&cmt_send_data);



    s_cb_data cb_data =
        { .reason = cbStartOfSimulation
          , .cb_rtn = sendrcv_simstart
          , .obj = NULL
          , .time = NULL
          , .value = NULL
          , .user_data = NULL
        };
    vpi_register_cb(&cb_data);

}

//
// At the start of the simulation, prepare global constants.
//
PLI_INT32 sendrcv_simstart(s_cb_data *callback_data) {
    (void) callback_data;

    mpz_init(t1);
    mpz_init(t2);

    for (int i = 0; i < MPZ_BUF_LEN; i++)
        mpz_init(mpz_buf[i]);


    server.sun_family = AF_UNIX;

    char socket_path[1000];
    getSocketPath(socket_path);
    strcpy(server.sun_path, socket_path);

    return 0;
}


static PLI_INT32 cmt_send_call(PLI_BYTE8 *user_data) {
    (void) user_data;

    vpiHandle* arg_iter = get_arg_iter();

    int id = get_int_arg(arg_iter);
    int sendType = get_int_arg(arg_iter);

    vpiHandle array_handle = NULL, element_handle = NULL;


    array_handle = vpi_scan(*arg_iter);

    int howMany = 0, layer = 0, round = 0;

    switch (sendType) {
    case CMT_OUTPUT:
        howMany = get_int_arg(arg_iter);
        layer = -1;
        round = -1;
        break;
    case CMT_F012:
        howMany = 3;
        layer = get_int_arg(arg_iter);
        round = get_int_arg(arg_iter);
        break;
    case CMT_H:
        layer = get_int_arg(arg_iter);
        howMany = get_int_arg(arg_iter);
        round = -1;
        break;
    }

    free(arg_iter);
    s_vpi_value arg_val = {0,};
    arg_val.format = vpiVectorVal;
    int arg_type = vpi_get(vpiType, array_handle);
    if ((arg_type == vpiReg)|| (arg_type == vpiMemoryWord)) {
        if (howMany == 1) {

            vpi_printf("NOTE: sending a single element. ($cmt_send called on a register or wire.) This is supported for debugging purposes, but probably shouldn't ever happen in the actual protocol.\n");
            //actually the element handle, since we weren't given an array.
            vpi_get_value(array_handle, &arg_val);
            from_vector_val(mpz_buf[0], arg_val.value.vector, vpi_get(vpiSize, array_handle));
        }

        else
            vpi_printf("ERROR: cmt_send called on a (non-array) register or wire, but howMany != 1.\n");
    }

    else {
        for (int i = 0; i < howMany; i++) {

            element_handle = vpi_handle_by_index(array_handle, i);
            vpi_get_value(element_handle, &arg_val);
            from_vector_val(mpz_buf[i], arg_val.value.vector, vpi_get(vpiSize, element_handle));
        }
    }

    prover_request request;
    request.howMany = howMany;
    request.id = id;
    request.requestType = sendType;
    request.layer = layer;
    request.round = round;

    put_cmt_io(mpz_buf, request);

    net_send(request);

    return 0;

}

static void net_recieve(prover_request request) {

    int sock = connect_to_ver();
    if (sock < 0) {
        return;
    }
    FILE* readfp = fdopen(sock, "r");

    sendHeader(request, sock);

    prover_request response = recieveHeader(readfp);
    check_header(response, request);

    if (request.requestType == CMT_MUXSEL)
        recieveMuxBits(muxBitsBuf, request.howMany, readfp);
    else
        recieveMPZ(request.howMany, readfp);

    close(sock);
    fclose(readfp);
}

static void check_header(prover_request response, prover_request request) {
    if ( (response.id != request.id) &&
         (response.requestType != request.requestType) &&
         (response.howMany != request.howMany) &&
         (response.round != request.layer) &&
         (response.layer != request.layer) ) {
        vpi_printf("ERROR: unexpected response from verifier in header. Giving up.\n");
        vpi_control(vpiFinish, 1);
    }

}

static int connect_to_ver() {
    int sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sock < 0) {
        perror("opening stream socket");
        vpi_control(vpiFinish, 1);
    }

    if (connect(sock, (struct sockaddr *) &server, sizeof(struct sockaddr_un)) < 0) {
        close(sock);
        perror("connecting stream socket");
        vpi_printf("(you must run the verifier in a seperate terminal before starting the simulation)\n");
        vpi_control(vpiFinish, 1);
        return -1;
    }

    return sock;
}

static void net_send(prover_request sendRequest) {

    int sock = connect_to_ver();
    if (sock < 0) {
        return;
    }

    FILE* readfp = fdopen(sock, "r");

    sendHeader(sendRequest, sock);
    sendMPZ(sendRequest.howMany, sock);

    close(sock);
    fclose(readfp);
}


static PLI_INT32 cmt_init_call(PLI_BYTE8 * user_data) {
    (void) user_data;

    int id = nextId++;

    vpiHandle* arg_iter = get_arg_iter();
    int maxWidth = get_int_arg(arg_iter);
    int depth = get_int_arg(arg_iter);

    free(arg_iter);
    init_cmt_io(id, maxWidth, depth);

    s_vpi_value retval = {0,};
    retval.format = vpiIntVal;
    vpiHandle systf_handle;
    systf_handle = vpi_handle(vpiSysTfCall, NULL);

    retval.value.integer = id;
    vpi_put_value(systf_handle, &retval, NULL, vpiNoDelay);

    return 0;

}


static PLI_INT32 cmt_request_call(PLI_BYTE8 * user_data) {
    (void) user_data;

    vpiHandle* arg_iter = get_arg_iter();

    int id = get_int_arg(arg_iter);
    int requestType = get_int_arg(arg_iter);


    vpiHandle array_handle = NULL, element_handle = NULL;
    array_handle = vpi_scan(*arg_iter);

    int howMany = 0, layer = 0, round = 0;

    switch (requestType) {
    case CMT_INPUT:
    case CMT_Q0:
        howMany = get_int_arg(arg_iter);
        layer = -1;
        round = -1;
        break;
    case CMT_R:
        howMany = 1;
        layer = get_int_arg(arg_iter);
        round = get_int_arg(arg_iter);
        break;
    case CMT_TAU:
        howMany = 1;
        layer = get_int_arg(arg_iter);
        round = -1;
        break;
    case CMT_QI:
        layer = get_int_arg(arg_iter);
        howMany = get_int_arg(arg_iter);
        round = -1;
    case CMT_MUXSEL:
        layer = -1;
        howMany = get_int_arg(arg_iter);
        round = -1;
        break;
    }

    free(arg_iter);


    prover_request request;
    request.howMany = howMany;
    request.id = id;
    request.requestType = requestType;
    request.layer = layer;
    request.round = round;
    net_recieve(request);


     s_vpi_value retval = {0,};
     retval.format = vpiVectorVal;
     PLI_INT32 arg_type = vpi_get(vpiType, array_handle);

    if (request.requestType == CMT_MUXSEL) {
        if (request.howMany > 0) {
            if ( (arg_type != vpiReg) ) {
                vpi_printf("ERROR: $cmt_request requested mux bits but argument is not a single register.\n");
                vpi_control(vpiFinish, 1);
            }
            int numBits = vpi_get(vpiSize, array_handle);

            if (request.howMany != numBits) {
                vpi_printf("ERROR: howMany should be the size of the register in bits when requesting mux bits\n");
                vpi_control(vpiFinish, 1);
            }

            int num_limbs = (numBits / 32) + (numBits % 32 != 0);
            s_vpi_vecval retvec[num_limbs];
            memset(retvec, 0, sizeof(retvec[0]) * num_limbs);

            for (int i = 0; i < numBits; i++) {
                if (muxBitsBuf[i]) {
                    retvec[i / 32].aval |= 1 << (i % 32);
                }
            }

            retval.value.vector = retvec;
            vpi_put_value(array_handle, &retval, NULL, vpiNoDelay);
        }
    }

    else {

        if (howMany == 1) {
            if ( (arg_type != vpiReg) && (arg_type != vpiMemoryWord) ) {
                vpi_printf("ERROR: $cmt_request called with howMany == 1 but argument is not a single register.\n");
                vpi_control(vpiFinish, 1);
            }
            retval.value.vector = to_vector_val(mpz_buf[0]);
            vpi_put_value(array_handle, &retval, NULL, vpiNoDelay);
        }

        else {
            for (int i = 0; i < howMany; i++) {
                element_handle = vpi_handle_by_index(array_handle, i);
                retval.value.vector = to_vector_val(mpz_buf[i]);
                vpi_put_value(element_handle, &retval, NULL, vpiNoDelay);
            }

        }



        put_cmt_io(mpz_buf, request);
    }

    return 0;

}







