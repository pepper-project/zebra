#include <iostream>
#include <gmp.h>

#include <stdbool.h>
#include <cstdio>
#include <cstring>

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>


#include <sys/uio.h>
#include <unistd.h>

#include "verifier_precomp.h"
#include "verifier_comp_state.h"


extern "C" {
#include "util.h"
}



#define MAX_NUM_CONNECTIONS 1
static int listen_sock;
static struct sockaddr_un server;


void initConnection(void);


void handle(prover_request request, FILE* readfp, int socket, VerifierPrecomputation* precomp, VerifierCompState* verState);


