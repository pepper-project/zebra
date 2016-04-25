//compile time typechecking and return size specification for sendrcv
//vpi functions.

#include "sendrcv_typechecker.h"
static bool isValidGetRequest(int requestType);
static bool isValidSend(int requestType);

PLI_INT32 cmt_init_comp(PLI_BYTE8 * user_data) {
    (void) user_data;

    vpiHandle systf_handle, arg_handle, arg_iter = NULL;
    PLI_INT32 arg_type;
    bool err = false;

    systf_handle = vpi_handle(vpiSysTfCall, NULL);
    arg_iter = vpi_iterate(vpiArgument, systf_handle);

    if (arg_iter == NULL) {
        vpi_printf("ERROR: $cmt_init takes exactly 2 arguments\n");
        err = true;
        goto INIT_COMP_FINISH;
    }

    //scan for first argument
    arg_handle = vpi_scan(arg_iter);
    arg_type = vpi_get(vpiType, arg_handle);


    if ( (arg_type != vpiConstant) && (arg_type != vpiIntegerVar) && (arg_type != vpiParameter) ) {
        vpi_printf("first argument to $cmt_init should be an integer specifying the maximum width of the cmt circuit.\n");
        err = true;
        goto INIT_COMP_FINISH;
    }

    //scan for second arguement
    arg_handle = vpi_scan(arg_iter);
    if (arg_handle == NULL) {
        arg_iter = NULL; // according to the standard, once vpi_scan returns NULL, the iterator is freed
        vpi_printf("ERROR: $cmt_init takes exactly 2 arguments\n");
        err = true;
        goto INIT_COMP_FINISH;
    }


    arg_type = vpi_get(vpiType, arg_handle);
    if ( (arg_type != vpiConstant) && (arg_type != vpiIntegerVar) && (arg_type != vpiParameter) ) {
        vpi_printf("ERROR: Second argument to $cmt_init should be an integer specifying the depth of the cmt cricuit.\n");
        err = true;
        goto INIT_COMP_FINISH;
    }

    if (vpi_scan(arg_iter) != NULL) {
        vpi_printf("ERROR: $cmt_init takes exactly 2 arguments");
        err = true;
        goto INIT_COMP_FINISH;
    } else {    // vpi_scan(arg_iter) returned NULL, so arg_iter was automatically freed
        arg_iter = NULL;
    }

INIT_COMP_FINISH:
    // free the iterator unless it's already been freed
    if ( (arg_iter != NULL) && (vpi_scan(arg_iter) != NULL) ) {
        vpi_free_object(arg_iter);
    }

    if (err) {
        vpi_control(vpiFinish, 1);
    }

    return 0;
}

PLI_INT32 cmt_init_size(PLI_BYTE8 * user_data) {
    (void) user_data;
    return 32;  //cmt_init returns a 32 bit verilog integer.
}

PLI_INT32 cmt_request_comp(PLI_BYTE8 * user_data) {
    (void) user_data;

    vpiHandle systf_handle, arg_handle, arg_iter = NULL;
    PLI_INT32 arg_type;
    bool err = false;

    systf_handle = vpi_handle(vpiSysTfCall, NULL);
    arg_iter = vpi_iterate(vpiArgument, systf_handle);

    if (arg_iter == NULL) {
        vpi_printf("ERROR: $cmt_request takes at least 3 arguments\n");
        err = true;
        goto REQUEST_COMP_FINISH;
    }

    //scan for first argument
    arg_handle = vpi_scan(arg_iter);
    arg_type = vpi_get(vpiType, arg_handle);

    if ( (arg_type != vpiConstant) && (arg_type != vpiIntegerVar) && (arg_type != vpiReg) && (arg_type != vpiNet) ) {
        vpi_printf("ERROR: First argument to $cmt_request should be the id of the cmt computation.\n");
        err = true;
        goto REQUEST_COMP_FINISH;
    }

    //scan for second argument
    arg_handle = vpi_scan(arg_iter);
    if (arg_handle == NULL) {
        arg_iter = NULL; // according to the standard, once vpi_scan returns NULL, the iterator is freed
        vpi_printf("ERROR: $cmt_request takes at least 4 arguments\n");
        err = true;
        goto REQUEST_COMP_FINISH;
    }


    arg_type = vpi_get(vpiType, arg_handle);
    if ( (arg_type != vpiConstant) && (vpi_get(vpiConstType, arg_handle) != vpiDecConst ) ) {
        vpi_printf("ERROR: second argument to $cmt_request should be an integer constant CMT_*\n");
        err = true;
        goto REQUEST_COMP_FINISH;
    }

    s_vpi_value arg_val = {0,};
    arg_val.format = vpiIntVal;
    vpi_get_value(arg_handle, &arg_val);
    int requestType = arg_val.value.integer;

    if (!isValidGetRequest(requestType)) {
        arg_iter = NULL;
        vpi_printf("ERROR: Invalid reuquestType constant in $cmt_request\n");
        err = true;
        goto REQUEST_COMP_FINISH;
    }


    //scan for third argument
    arg_handle = vpi_scan(arg_iter);
    if (arg_handle == NULL) {
        arg_iter = NULL; // according to the standard, once vpi_scan returns NULL, the iterator is freed
        vpi_printf("ERROR: $cmt_request takes at least 4 arguments\n");
        err = true;
        goto REQUEST_COMP_FINISH;
    }

    arg_type = vpi_get(vpiType, arg_handle);

    if ((arg_type != vpiReg) && (arg_type != vpiMemory)   && (arg_type != vpiMemoryWord) && (arg_type != vpiRegArray) && (arg_type != vpiNetArray) ) {
        vpi_printf("ERROR: third argument to $cmt_request should be a vector of registers to send\n");
        err = true;
        goto REQUEST_COMP_FINISH;
    }

    if (requestType == CMT_R || requestType == CMT_TAU) {

        if ((arg_type != vpiMemoryWord) && (arg_type != vpiReg)) {
            vpi_printf("ERROR: if requesting  CMT_R or CMT_TAU, 3rd argument should be a single registor or memory word.\n");
        }

    }


    //scan for fourth argument
    arg_handle = vpi_scan(arg_iter);
    if (arg_handle == NULL) {
        arg_iter = NULL; // according to the standard, once vpi_scan returns NULL, the iterator is freed
        vpi_printf("ERROR: $cmt_request takes at least 4 arguments\n");
        err = true;
        goto REQUEST_COMP_FINISH;
    }

    arg_type = vpi_get(vpiType, arg_handle);
    if ( (arg_type != vpiConstant) && (arg_type != vpiParameter) ) {
        vpi_printf("ERROR: fourth argument to $cmt_request should be an integer specifying how many elements, or the layer of the computation. (%d) \n", arg_type);
        err = true;
        goto REQUEST_COMP_FINISH;
    }

    if ( (requestType == CMT_R) || (requestType == CMT_QI) ) {
        //scan for fifth argument
        arg_handle = vpi_scan(arg_iter);
        if (arg_handle == NULL) {
            arg_iter = NULL; // according to the standard, once vpi_scan returns NULL, the iterator is freed
            vpi_printf("ERROR: $cmt_request request requires 5 arguments when requesting CMT_R or CMT_QI.\n");
            err = true;
            goto REQUEST_COMP_FINISH;
        }

        arg_type = vpi_get(vpiType, arg_handle);
        if ( (arg_type != vpiConstant) && (arg_type != vpiParameter) && (arg_type != vpiIntegerVar) && (arg_type != vpiReg) && (arg_type != vpiNet) ) {
            vpi_printf("ERROR: fifth argument to $cmt_request should be an integer specifying how many elements of QI, or which round of sumcheck, for R. \n");
            err = true;
            goto REQUEST_COMP_FINISH;
        }

    }


    if (vpi_scan(arg_iter) != NULL) {
        vpi_printf("ERROR: $cmt_request takes four or five arguments");
        err = true;
        goto REQUEST_COMP_FINISH;
    } else {    // vpi_scan(arg_iter) returned NULL, so arg_iter was automatically freed
        arg_iter = NULL;
    }

REQUEST_COMP_FINISH:
    // free the iterator unless it's already been freed
    if ( (arg_iter != NULL) && (vpi_scan(arg_iter) != NULL) ) {
        vpi_free_object(arg_iter);
    }

    if (err) {
        vpi_control(vpiFinish, 1);
    }

    return 0;

}


PLI_INT32 cmt_send_comp(PLI_BYTE8 *user_data) {
    (void) user_data;

    vpiHandle systf_handle, arg_handle, arg_iter = NULL;
    PLI_INT32 arg_type;
    bool err = false;

    systf_handle = vpi_handle(vpiSysTfCall, NULL);
    arg_iter = vpi_iterate(vpiArgument, systf_handle);

    if (arg_iter == NULL) {
        vpi_printf("ERROR: $cmt_send takes at least 4 arguments\n");
        err = true;
        goto SEND_COMP_FINISH;
    }

    //scan for first argument
    arg_handle = vpi_scan(arg_iter);
    arg_type = vpi_get(vpiType, arg_handle);


    if ( (arg_type != vpiConstant) && (arg_type != vpiIntegerVar) && (arg_type != vpiReg) && (arg_type != vpiNet) ) {
        vpi_printf("first argument to $cmt_send should be the id of the cmt computation.");
        err = true;
        goto SEND_COMP_FINISH;
    }

    //scan for second arguement
    arg_handle = vpi_scan(arg_iter);
    if (arg_handle == NULL) {
        arg_iter = NULL; // according to the standard, once vpi_scan returns NULL, the iterator is freed
        vpi_printf("ERROR: $cmt_send takes at least 4 arguments\n");
        err = true;
        goto SEND_COMP_FINISH;
    }

    arg_type = vpi_get(vpiType, arg_handle);
    if ( (arg_type != vpiConstant) && (arg_type != vpiIntegerVar) && (arg_type != vpiReg) && (arg_type != vpiNet)) {
        vpi_printf("ERROR: Second argument to $cmt_send should be an integer constant CMT_*\n");
        err = true;
        goto SEND_COMP_FINISH;
    }

    s_vpi_value arg_val = {0,};
    arg_val.format = vpiIntVal;
    vpi_get_value(arg_handle, &arg_val);
    int requestType = arg_val.value.integer;
#ifdef DEBUG
    vpi_printf("requestType in cmt_send: %d\n", requestType);
#endif


    //scan for third arguement
    arg_handle = vpi_scan(arg_iter);
    if (arg_handle == NULL) {
        arg_iter = NULL; // according to the standard, once vpi_scan returns NULL, the iterator is freed
        vpi_printf("ERROR: $cmt_send takes at least 4 arguments\n");
        err = true;
        goto SEND_COMP_FINISH;
    }

    arg_type = vpi_get(vpiType, arg_handle);
    if ( (arg_type != vpiReg) && (arg_type != vpiMemory) && (arg_type != vpiMemoryWord) && (arg_type != vpiNetArray) && (arg_type != vpiRegArray) ) {
        vpi_printf("ERROR: third argument to $cmt_send should be the field elements to send.\n");
        vpi_printf("arg_type: %d\n", arg_type);
        err = true;
        goto SEND_COMP_FINISH;
    }


    //scan for fourth argument
    arg_handle = vpi_scan(arg_iter);
    if (arg_handle == NULL) {
        arg_iter = NULL; // according to the standard, once vpi_scan returns NULL, the iterator is freed
        vpi_printf("ERROR: $cmt_request takes at least 4 arguments\n");
        err = true;
        goto SEND_COMP_FINISH;
    }

    arg_type = vpi_get(vpiType, arg_handle);
    if ( (arg_type != vpiConstant) && (arg_type != vpiParameter) ) {
        vpi_printf("ERROR: fourth argument to $cmt_send should be an integer specifying how many elements to send (CMT_OUTPUT, CMT_H) or the layer (CMT_F012).\n");
        err = true;
        goto SEND_COMP_FINISH;
    }

    if (!isValidSend(requestType)) {
        arg_iter = NULL;
        vpi_printf("ERROR: Invalid reuquestType constant in $cmt_send\n");
        err = true;
        goto SEND_COMP_FINISH;
    }


    if ((requestType == CMT_F012) || (requestType == CMT_H)) { //need a 5th argument in this case.

        arg_handle = vpi_scan(arg_iter);
        if (arg_handle == NULL) {
            arg_iter = NULL; // according to the standard, once vpi_scan returns NULL, the iterator is freed
            vpi_printf("ERROR: $cmt_send: you requested CMT_F012 without specifying a round, or CMT_H, without specifying a layer.\n");
            err = true;
            goto SEND_COMP_FINISH;
        }

        arg_type = vpi_get(vpiType, arg_handle);
        if ( (arg_type != vpiConstant) && (arg_type != vpiParameter) && (arg_type != vpiIntegerVar) && (arg_type != vpiReg) && (arg_type != vpiNet) ) {
            vpi_printf("ERROR: fifth argument to $cmt_send should be an integer specifying round or layer.\n");
            err = true;
            goto SEND_COMP_FINISH;
        }


    }

    if (vpi_scan(arg_iter) != NULL) {
        vpi_printf("ERROR: $cmt_send takes no more than 5 arguments.\n");
        err = true;
        goto SEND_COMP_FINISH;
    } else {    // vpi_scan(arg_iter) returned NULL, so arg_iter was automatically freed
        arg_iter = NULL;
    }

SEND_COMP_FINISH:
    // free the iterator unless it's already been freed
    if ( (arg_iter != NULL) && (vpi_scan(arg_iter) != NULL) ) {
        vpi_free_object(arg_iter);
    }

    if (err) {
        vpi_control(vpiFinish, 1);
    }

    return 0;
}

static bool isValidGetRequest(int requestType) {
    return ( (requestType == CMT_INPUT) || (requestType == CMT_Q0) || (requestType == CMT_R) || (requestType == CMT_TAU) || (requestType == CMT_QI) || requestType == CMT_MUXSEL);
}

static bool isValidSend(int requestType) {
        return ( (requestType == CMT_OUTPUT) || (requestType == CMT_F012) || (requestType == CMT_H));
}
