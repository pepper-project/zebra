// arith.c
// VPI module for field arithmetic
// defines two system functions: $f_add and $f_mul
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

#include "arith.h"

//
// Register $f_mul and $f_add with the Verilog simulator.
//
void arith_register(void) {

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

    s_vpi_systf_data add_data =
        { .type = vpiSysFunc
        , .sysfunctype = vpiSizedFunc
        , .tfname = "$f_add"
        , .calltf = add_call
        , .compiletf = addmul_comp
        , .sizetf = addmul_size
        , .user_data = NULL
        };
    vpi_register_systf(&add_data);

    s_vpi_systf_data mul_data =
        { .type = vpiSysFunc
        , .sysfunctype = vpiSizedFunc
        , .tfname = "$f_mul"
        , .calltf = mul_call
        , .compiletf = addmul_comp
        , .sizetf = addmul_size
        , .user_data = NULL
        };
    vpi_register_systf(&mul_data);

    s_cb_data cb_data_start =
        { .reason = cbStartOfSimulation
        , .cb_rtn = arith_simstart
        , .obj = NULL
        , .time = NULL
        , .value = NULL
        , .user_data = NULL
        };
    vpi_register_cb(&cb_data_start);

    s_cb_data cb_data_end =
        { .reason = cbEndOfSimulation
        , .cb_rtn = arith_simend
        , .obj = NULL
        , .time = NULL
        , .value = NULL
        , .user_data = NULL
        };
    vpi_register_cb(&cb_data_end);
}

//
// At the start of the simulation, prepare global constants.
//
PLI_INT32 arith_simstart(s_cb_data *callback_data) {
    (void) callback_data;

    // initialize the modulus
    mpz_init_set_ui(p, 1);
    mpz_mul_2exp(p, p, PRIMEBITS);
    mpz_sub_ui(p, p, PRIMEDELTA);

    // initialize temporary GMP variables
    mpz_init2(t1, 2*(PRIMEBITS + 1));
    mpz_init2(t2, 2*(PRIMEBITS + 1));

    // initialize logging for arithmetic operations
    memset(&add_log, 0, sizeof(add_log));
    memset(&mul_log, 0, sizeof(mul_log));
    add_log.size = LOG_INIT_SIZE;
    mul_log.size = LOG_INIT_SIZE;
    add_log.log = (uint64_t *) malloc(LOG_INIT_SIZE * sizeof(uint64_t));
    mul_log.log = (uint64_t *) malloc(LOG_INIT_SIZE * sizeof(uint64_t));

    if (add_log.log == NULL || mul_log.log == NULL) {
        vpi_control(vpiFinish, 1);
    }
    return 0;
}

//
// At the end of the simulation, report how many add and mul we used, and the timestamp of each
//
PLI_INT32 arith_simend(s_cb_data *callback_data) {
    (void) callback_data;
    vpi_printf("\n***\nArithmetic totals:\nadd %d\nmul %d\n(timestamps written to file)\n***\n\n", add_log.count, mul_log.count);

    FILE *logfile;
    char *fname;
    if ( (fname = getenv("ARITH_LOG_FILE")) != NULL ) {
        logfile = fopen(fname, "w");
    } else {
        logfile = fopen("arith_log.txt", "w");
    }

    // dump out the add log
    if (add_log.log != NULL) {
        fprintf(logfile, "ADD timesteps (%d): ", add_log.count);
        for (unsigned i = 0; i < add_log.count; i++) {
            fprintf(logfile, "%" PRIu64 ", ", add_log.log[i]);
        }
        fprintf(logfile, "\n");
        free(add_log.log);
    }

    // dump out the mul log
    if (mul_log.log != NULL) {
        fprintf(logfile, "MUL timesteps (%d): ", mul_log.count);
        for (unsigned i = 0; i < mul_log.count; i++) {
            fprintf(logfile, "%" PRIu64 ", ", mul_log.log[i]);
        }
        fprintf(logfile, "\n");
        free(mul_log.log);
    }

    fclose(logfile);

    return 0;
}

//
// This function is called once during elaboration to determine
// how many bits $f_add and $f_mul return.
//
static PLI_INT32 addmul_size(PLI_BYTE8 *user_data) {
    (void) user_data;

    return PRIMEBITS;
}

//
// This function is called once during elaboration for each
// instance of $f_add or $f_mul in a design. It checks that
// the arguments to that instance are well formed.
//
static PLI_INT32 addmul_comp(PLI_BYTE8 *user_data) {
    (void) user_data;

    vpiHandle systf_handle, arg_handle, arg_iter = NULL;
    PLI_INT32 arg_type;
    bool err = false;

    systf_handle = vpi_handle(vpiSysTfCall, NULL);
    arg_iter = vpi_iterate(vpiArgument, systf_handle);

    if (arg_iter == NULL) {
        vpi_printf("ERROR: $f_add/$f_mul takes exactly 2 arguments\n");
        err = true;
        goto ADDMUL_COMP_FINISH;
    }

    arg_handle = vpi_scan(arg_iter);
    arg_type = vpi_get(vpiType, arg_handle);
    // need a constant, an integer, a reg, or a net
    if ( (arg_type != vpiConstant) && (arg_type != vpiIntegerVar) && (arg_type != vpiReg) && (arg_type != vpiNet)  && (arg_type != vpiMemoryWord) ) {
        vpi_printf("ERROR: $f_add/$f_mul arguments must be number, variable, reg, or net\n");
        vpi_printf("arg_type: %d\n", arg_type);
        err = true;
        goto ADDMUL_COMP_FINISH;
    }

    arg_handle = vpi_scan(arg_iter);
    if (arg_handle == NULL) {
        arg_iter = NULL; // according to the standard, once vpi_scan returns NULL, the iterator is freed
        vpi_printf("ERROR: $f_add/$f_mul takes exactly 2 arguments\n");
        err = true;
        goto ADDMUL_COMP_FINISH;
    }

    arg_type = vpi_get(vpiType, arg_handle);
    if ( (arg_type != vpiConstant) && (arg_type != vpiIntegerVar) && (arg_type != vpiReg) && (arg_type != vpiNet   && (arg_type != vpiMemoryWord)) ) {
        vpi_printf("ERROR: $f_add/$f_mul arguments must be number, variable, reg, or net\n");
        err = true;
        goto ADDMUL_COMP_FINISH;
    }

    if (vpi_scan(arg_iter) != NULL) {
        vpi_printf("ERROR: $f_add/$f_mul takes exactly 2 arguments\n");
        err = true;
        goto ADDMUL_COMP_FINISH;
    } else {    // vpi_scan(arg_iter) returned NULL, so arg_iter was automatically freed
        arg_iter = NULL;
    }

ADDMUL_COMP_FINISH:
    // free the iterator unless it's already been freed
    if ( (arg_iter != NULL) && (vpi_scan(arg_iter) != NULL) ) {
        vpi_free_object(arg_iter);
    }

    if (err) {
        vpi_control(vpiFinish, 1);
    }

    return 0;
}

//
// This function runs each time $f_add or $f_mul is called.
// It retrieves arguments and converts them to mpz_t.
//
static bool get_args(vpiHandle systf_handle, s_vpi_value *val) {
    vpiHandle arg_handle;
    vpiHandle arg_iter = vpi_iterate(vpiArgument, systf_handle);

    if (arg_iter == NULL) {
        vpi_printf("ERROR: $f_add/$f_mul failed to get arg handle\n");
        return true;
    }

    arg_handle = vpi_scan(arg_iter);
    vpi_get_value(arg_handle, val);
    from_vector_val(t1, val->value.vector, vpi_get(vpiSize, arg_handle));

    arg_handle = vpi_scan(arg_iter);
    vpi_get_value(arg_handle, val);
    from_vector_val(t2, val->value.vector, vpi_get(vpiSize, arg_handle));

    vpi_free_object(arg_iter);
    return false;
}

//
// $f_add function. Gets args, computes result, and returns result to simulator.
//
static PLI_INT32 add_call(PLI_BYTE8 *user_data) {
    (void) user_data;

    // increment the call counter
    log_arith_op(0);

    // get arguments as hex strings
    s_vpi_value val = {0,};
    val.format = vpiVectorVal;
    vpiHandle systf_handle;

    systf_handle = vpi_handle(vpiSysTfCall, NULL);

    if (get_args(systf_handle, &val)) {
        // error getting args; abort
        vpi_control(vpiFinish, 1);
    } else {
        mpz_add(t2, t2, t1);
        mpz_mod(t2, t2, p);
        val.value.vector = to_vector_val(t2);
        vpi_put_value(systf_handle, &val, NULL, vpiNoDelay);
    }

    return 0;
}

//
// $f_mul function. Gets args, computes result, and returns result to simulator.
//
static PLI_INT32 mul_call(PLI_BYTE8 *user_data) {
    (void) user_data;

    // increment the call counter
    log_arith_op(1);

    // get arguments as hex strings
    s_vpi_value val = {0,};
    val.format = vpiVectorVal;
    vpiHandle systf_handle;

    systf_handle = vpi_handle(vpiSysTfCall, NULL);

    if (get_args(systf_handle, &val)) {
        // error getting args; abort
        vpi_control(vpiFinish, 1);
    } else {
        mpz_mul(t2, t2, t1);
        mpz_mod(t2, t2, p);
        val.value.vector = to_vector_val(t2);
        vpi_put_value(systf_handle, &val, NULL, vpiNoDelay);
    }

    return 0;
}

//
// log an arithmetic operation
//
static void log_arith_op(bool is_mul) {
    s_arith_log *arith_log;

    // select the proper log
    if (is_mul) {
        arith_log = &mul_log;
    } else {
        arith_log = &add_log;
    }

    // increment the counter
    arith_log->count++;
    if (arith_log->count > arith_log->size) {
        arith_log->size *= 2;
        if ( (arith_log->log = realloc(arith_log->log, arith_log->size * sizeof(uint64_t))) == NULL) {
            vpi_control(vpiFinish, 1);
        }
    }

    // now store the timestamp
    s_vpi_time time_s = { .type = vpiSimTime, .high = 0, .low = 0, .real = 0 };
    vpi_get_time(NULL, &time_s);
    arith_log->log[arith_log->count - 1] = ((uint64_t) time_s.high << 32) | time_s.low;
}
