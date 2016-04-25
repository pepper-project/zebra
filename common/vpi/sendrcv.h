#include <gmp.h>

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>


#include <sys/uio.h>
#include <unistd.h>

#include <vpi_user.h>
// for ncverilog only
#ifdef HAVE_VPI_USER_CDS_H
#include <vpi_user_cds.h>
#endif

#include "vpi_util.h"
#include "util.h"



static struct sockaddr_un server;

static int nextId = 0;


static PLI_INT32 cmt_init_call(PLI_BYTE8 *user_data);
static PLI_INT32 cmt_request_call(PLI_BYTE8 *user_data);
static PLI_INT32 cmt_send_call(PLI_BYTE8 *user_data);

// we can reuse the same mpz_t for everything
static mpz_t t1, t2;

void sendrcv_register(void);
PLI_INT32 sendrcv_simstart(s_cb_data *callback_data);

// verilog simulator will call sendrcv_register at initialization
void (*vlog_startup_routines[])(void) = { sendrcv_register, 0, };

// send/recieve the first howMany mpz elements in mpz_buff.
static void net_recieve(prover_request request);
static void net_send(prover_request sendRequest);
static int connect_to_ver(void);
static void check_header(prover_request response, prover_request request);


