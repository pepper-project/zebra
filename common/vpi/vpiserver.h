// vpiserver.h
// header for VPI module defining verifier side of V-P interface
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

#include <gmp.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/uio.h>
#include <unistd.h>
#include <poll.h>

#include <vpi_user.h>
// for ncverilog only
#ifdef HAVE_VPI_USER_CDS_H
#include <vpi_user_cds.h>
#endif

#include "cmtprecomp.h"
#include "vpi_util.h"
#include "util.h"

// socket is open over the life of the simulation
#define MAX_NUM_CONNECTIONS 1
#define TIMEOUT (1024 * 2)

extern mpz_t mpz_buf[]; // from util.c
static int listen_sock;
static struct pollfd pfds = { 0, };
static struct sockaddr_un server = { 0, };
static bool hwver_init;
static cmtprecomp_cdata pc_data[PIPELINE_DEPTH];

// register functions with verilog simulator
void vpiserver_register(void);

// init and deinit
static PLI_INT32 vpiserver_simstart(s_cb_data *callback_data);
static PLI_INT32 vpiserver_simend(s_cb_data *callback_data);

static PLI_INT32 verifier_update_call(PLI_BYTE8 *user_data);
static PLI_INT32 verifier_poll_call(PLI_BYTE8 *user_data);

//NOTE: not currently implemented. No compile time checking!
static PLI_INT32 verifier_update_comp(PLI_BYTE8 *user_data);
static PLI_INT32 verifier_poll_comp(PLI_BYTE8 *user_data);
// create a new computation
static void new_comp(prover_request request);

// show the verilog simulator what we've got
void (*vlog_startup_routines[])(void) = { vpiserver_register, 0, };

//handle the provers request: either send or recieve stuff.
void handleReq(prover_request request, FILE* readfp, int write_socket);
//called after handleReq, if we need to return values to V.
void returnValues(prover_request request);

//check the phase, etc. is correct (and update it), and move the
//requested data into mpz_buf for sending.
void prepareInputs(prover_request request);
void prepareQ0(prover_request request);
void prepareR(prover_request request);
void prepareT(prover_request request);
