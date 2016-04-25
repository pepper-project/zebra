#pragma once

#include <gmp.h> 
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdbool.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>

#include <sys/uio.h>
#include <unistd.h>

// uncomment the below to use p = 2^255 - 19
// NOTE you must also `define USE_P25519 in simulator.v
#define USE_P25519

#ifndef USE_P25519

// 2^61 - 1
#define PRIMEBITS 61
#define PRIMEDELTA 1
#define PRIMEC32 2

#else

#define PRIMEBITS 255
#define PRIMEDELTA 19
#define PRIMEC32 8

//use mpfq for field arithmetic of protocol checks
//note: mpfq supports other fields but currently verifier only
//implements it for 25519

#ifndef INHIBIT_MPFQ
#define USE_MPFQ
#endif

#endif
/*
 * NOTE
 * If you change the above, you should also modify
 * bit widths of registers set by $f_add and $f_mul,
 * and you need to update the arith.sft file to
 * reflect the width of the outputs.
 */

//data the prover requests
#define CMT_INPUT 10000 //request: howMany
#define CMT_Q0 20000    //request: howMany
#define CMT_R 30000    //request: layer, round. 
#define CMT_TAU 40000  //request: layer 
#define CMT_QI 50000   //request: layer, how many
#define CMT_MUXSEL 55000 //request: how many bits, 
//data the prover sends
#define CMT_OUTPUT 60000 //send: howMany
#define CMT_F012 70000   //send: layer, round
#define CMT_H  90000    //send: layer, howMany.

#define SEND_INPUTS 0
#define CHECK_OUTPUTS 1
#define SEND_Q0 2
#define CHECK_F012 3
#define SEND_NEXT_R 4
#define CHECK_H 5
#define SEND_NEXT_QI_OR_TAU 6

// the debug macro causes P and V both to dump copious messages about their communication
//#define DEBUG

#define MPZ_BUF_LEN 16384

//for timing the verifier's checks
#define BILLION 1000000000L

#ifdef DEBUG
  #define NREPS 1 //number of times to repeat the checks.
#else
  #define NREPS 1000
#endif

#define SOCKET_NAME "cmthw_socket"
//determines how many cmt_io_buf structs and verifier_comp_state objs to allocate
#define PIPELINE_DEPTH 80


typedef struct cmt_io cmt_io;
typedef struct sumcheck_io sumcheck_io;

struct cmt_io {
    int id;
    int maxWidth;
    int logMaxWidth;
    int depth;
    mpz_t* input; //maxWidth-length array
    mpz_t* output; //maxWidth-length array
    mpz_t* q0; //log2(maxWidth)-length array
    sumcheck_io* layer_io; //depth-length array
};


struct sumcheck_io {
    mpz_t (*F012)[3]; //2*log2(width) x 3 array
    mpz_t* r; // 2*log2(width) array for 2 * log2(width) rounds of sc protocol.
    mpz_t* H;//log(width) + 1 array
    mpz_t T; //tau. 
    mpz_t* qi; //log(width) length array for q_i.

};

typedef struct prover_request prover_request;
struct prover_request {
    int id;
    int requestType;
    int howMany;
    int round;
    int layer;
};


void init_cmt_io(int id, int maxWidth, int depth);
void put_cmt_io(mpz_t* toPut, prover_request request);

void sendHeader(prover_request request, int socket);
prover_request recieveHeader(FILE* readfp);
void recieveMPZ(int HowMany, FILE* readfp);
void sendMPZ(int howMany, int socket);
void sendMuxBits(bool* muxBits, int numMuxBits, int socket);
void recieveMuxBits(bool* muxBits, int numMuxBits,  FILE* readfp);

char* phaseToStr(int phase);
char * requestToStr(int request);
void getSocketPath(char* socket_path);

bool verifierSendsOn(prover_request request);
bool verifierRecievesOn(prover_request request);
