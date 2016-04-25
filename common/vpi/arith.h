// arith.h
// VPI module for field arithmetic (header)
// defines two system functions: $f_add and $f_mul
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

#include <gmp.h>

#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <vpi_user.h>
// for ncverilog only
#ifdef HAVE_VPI_USER_CDS_H
#include <vpi_user_cds.h>
#endif

#include "vpi_util.h"

static PLI_INT32 addmul_comp(PLI_BYTE8 *user_data);
static PLI_INT32 addmul_size(PLI_BYTE8 *user_data);


static bool get_args(vpiHandle systf_handle, s_vpi_value *val);
static PLI_INT32 add_call(PLI_BYTE8 *user_data);
static PLI_INT32 mul_call(PLI_BYTE8 *user_data);

// we can reuse the same mpz_t for everything
static mpz_t p, t1, t2;

void arith_register(void);
PLI_INT32 arith_simstart(s_cb_data *callback_data);
PLI_INT32 arith_simend(s_cb_data *callback_data);

// verilog simulator will call arith_register at initialization
void (*vlog_startup_routines[])(void) = { arith_register, 0, };

// arith logging struct
typedef struct {
    unsigned count;
    unsigned size;
    uint64_t *log;
} s_arith_log;

#define LOG_INIT_SIZE 1024
static s_arith_log add_log, mul_log;
static void log_arith_op(bool is_mul);
