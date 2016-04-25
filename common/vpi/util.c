
#include "util.h"

#include <math.h>
#include <assert.h>

//global variables
mpz_t mpz_buf[MPZ_BUF_LEN];
cmt_io cmt_io_buf[PIPELINE_DEPTH];
int netBytesRecieved = 0;
int netBytesSent = 0;
static void init_sumcheck_io(sumcheck_io* layer_io, int logMaxWidth);
static char buf[32768];

void init_cmt_io(int id, int maxWidth, int depth) {
    cmt_io* the_one = &cmt_io_buf[id];
    
    the_one->maxWidth = maxWidth;
    the_one->depth = depth;
    int logMaxWidth = (int) ceil(log2(maxWidth));
    the_one->logMaxWidth = logMaxWidth;
    the_one->input = malloc(sizeof(mpz_t) * maxWidth);
    the_one->output = malloc(sizeof(mpz_t) * maxWidth);
    the_one->q0 = malloc(sizeof(mpz_t) * logMaxWidth);

    for (int i = 0; i < maxWidth; i++) {
        mpz_init(the_one->input[i]);
        mpz_init(the_one->output[i]);
    }

    for (int i = 0; i < logMaxWidth; i++)
        mpz_init(the_one->q0[i]);

    the_one->layer_io = malloc(sizeof(sumcheck_io) * depth);
    for (int i = 0; i < depth; i++) {
        init_sumcheck_io(&(the_one->layer_io[i]), logMaxWidth);
    }

}


void put_cmt_io(mpz_t* toPut, prover_request request) {
    cmt_io* the_one = &cmt_io_buf[request.id % PIPELINE_DEPTH];
    //printf("request.howMany: %d\n the_one->maxWidth: %d\n", request.howMany, the_one->maxWidth);
    assert(request.howMany <= the_one->maxWidth);
    switch (request.requestType) {
    case CMT_INPUT:
        for (int i = 0; i < request.howMany; i++)
            mpz_set(the_one->input[i], toPut[i]);
        break;
    case CMT_OUTPUT:
        for (int i = 0; i < request.howMany; i++)            
            mpz_set(the_one->output[i], toPut[i]);
        break;
    case CMT_Q0:
        for (int i = 0; i < request.howMany; i++)
            mpz_set(the_one->q0[i], toPut[i]);
        break;
    case CMT_F012:
        for (int i = 0; i < request.howMany; i++)
            mpz_set(the_one->layer_io[request.layer].F012[request.round][i], toPut[i]);
        break;
    case CMT_R:
        mpz_set(the_one->layer_io[request.layer].r[request.round], toPut[0]);
        break;
    case CMT_H:
        for (int i = 0; i < request.howMany; i++)
            mpz_set(the_one->layer_io[request.layer].H[i], toPut[i]);
        break;
    case CMT_TAU:
        mpz_set(the_one->layer_io[request.layer].T, toPut[0]);
        break;
    case CMT_QI:
        for (int i = 0; i < request.howMany; i++)
            mpz_set(the_one->layer_io[request.layer].qi[i], toPut[i]);
        break;
    default:
        printf("ERROR: bad header in put_cmt_io\n");
        break;
    }
}


static void init_sumcheck_io(sumcheck_io * layer_io, int logMaxWidth) {

    layer_io->F012 = malloc(sizeof(mpz_t[3]) * 2 * logMaxWidth);
    for (int i = 0; i < 2 * logMaxWidth; i++) {
        mpz_init(layer_io->F012[i][0]);
        mpz_init(layer_io->F012[i][1]);
        mpz_init(layer_io->F012[i][2]);
    }

    layer_io->r = malloc(sizeof(mpz_t) * 2 * logMaxWidth);
    for (int i = 0; i < 2 * logMaxWidth; i++)
        mpz_init(layer_io->r[i]);

    layer_io->H = malloc(sizeof(mpz_t) * (logMaxWidth + 1));
    for (int i = 0; i < logMaxWidth + 1; i++)
        mpz_init(layer_io->H[i]);

    mpz_init(layer_io->T);

    layer_io->qi = malloc(sizeof(mpz_t) * logMaxWidth);
    for (int i = 0; i < logMaxWidth; i++)
        mpz_init(layer_io->qi[i]);


}


void sendHeader(prover_request request, int socket) {

    sprintf(buf, "%d, %d, %d, %d, %d: ", request.id, request.requestType, request.howMany, request.round, request.layer);

    if (write(socket, buf, strlen(buf)) < 0)
        perror("writing on stream socket");

    netBytesSent += strlen(buf);
#ifdef DEBUG
    printf("\n\nsending request for: %s. for computation id %d\n", requestToStr(request.requestType), request.id);
#endif

}


void sendMPZ(int howMany, int socket) {
#ifdef DEBUG
    printf("sending %d mpz's: ", howMany);
#endif

    for (int i = 0; i < howMany; i++) {
        gmp_sprintf(buf, "%Zd,", mpz_buf[i]);
#ifdef DEBUG
        printf("%s", buf);
#endif
        if (write(socket, buf, strlen(buf)) < 0)
            perror("writing on stream socket");
    }

    netBytesSent += strlen(buf);
#ifdef DEBUG
    printf("\n");
#endif
}

void sendMuxBits(bool* muxBits, int numMuxBits, int socket) {
    
    for (int i = 0; i < numMuxBits; i++) {
        if (muxBits[i])
            buf[i] = '0';
        else
            buf[i] = '1';
    }
    buf[numMuxBits] = 0;

    if (write(socket, buf, strlen(buf)) < 0)
        perror("writing on stream socket");
    
    netBytesSent += strlen(buf);
#ifdef DEBUG
    printf("sent muxBits: %s\n", buf);
#endif

}


void recieveMuxBits(bool* muxBits, int numMuxBits, FILE* readfp) {
    char c;
    for (int i = 0; i < numMuxBits; i++) {
        c = fgetc(readfp);
        if (c == '1')
            muxBits[i] = true;
        else
            muxBits[i] = false;
    }
#ifdef DEBUG
    printf("recieved muxBits: ");
    for (int i = 0; i < numMuxBits; i++) {
        printf("%d, ", muxBits[i]);
    }
    printf("\n");
#endif

}

void recieveMPZ(int howMany, FILE* readfp) {
    char c;

#ifdef DEBUG
    printf("waiting for %d mpz's\n", howMany);
#endif
    for (int i = 0; i < howMany; i++) {
        for (int j = 0; (c = fgetc(readfp)) != EOF; j++) {
            netBytesRecieved++;
            buf[j] = c;
                
            if (c == ',') {
                buf[j] = 0;
                break;
            }
        }
        gmp_sscanf(buf, "%Zd", mpz_buf[i]);
        netBytesRecieved += strlen(buf);
    }

#ifdef DEBUG
    gmp_printf("received: ");
    for (int i = 0; i < howMany; i++) {
        gmp_printf("%Zd,", mpz_buf[i]);
    }
    gmp_printf("\n");
#endif
}


prover_request recieveHeader(FILE* readfp) {
    char c;
    prover_request request;

    for (int j = 0; (c = fgetc(readfp)) != EOF; j++) {
        buf[j] = c;
        
        if (c == ':') {
            buf[j] = 0;
            break;
        }
    }

    sscanf(buf, "%d, %d, %d, %d, %d", &request.id, &request.requestType, &request.howMany, &request.round, &request.layer);
    netBytesRecieved += strlen(buf);

#ifdef DEBUG
    printf("\n\nrecieved request: %s. for computation id %d\n", requestToStr(request.requestType), request.id);
#endif

    return request;
}


char* phaseToStr(int phase) {
    switch(phase) {
    case SEND_INPUTS:
        return "SEND_INPUTS";
    case CHECK_OUTPUTS:
        return "CHECK_OUTPUTS";
    case SEND_Q0:
        return "SEND_Q0";
    case CHECK_F012:
        return "CHECK_F012";
    case SEND_NEXT_R:
        return "SEND_NEXT_R";
    case  CHECK_H:
        return "CHECK_H";
    case SEND_NEXT_QI_OR_TAU:
        return "SEND_NEXT_QI_OR_TAU";
    default:
        printf("ERROR: not a valid phase. exiting\n");
        exit(1);

    }

}

char * requestToStr(int request) {
    switch(request) {
    case CMT_INPUT:
        return "CMT_INPUT";
    case CMT_Q0:
        return "CMT_Q0";
    case CMT_R:
        return "CMT_R";
    case CMT_TAU:
        return "CMT_TAU";
    case CMT_QI:
        return "CMT_QI";
    case CMT_MUXSEL:
        return "CMT_MUXSEL";
    case CMT_OUTPUT:
        return "CMT_OUTPUT";
    case CMT_F012:
        return "CMT_F012";
    case CMT_H:
        return "CMT_H";
    default:
        printf("ERROR: not a vaild request type. exiting\n");
        exit(1);
    }

}

void getSocketPath(char* socket_path) {

    char* user_socket_path = getenv("CMT_SOCK_PATH");
    if (user_socket_path != NULL) {
        sprintf(socket_path, "%s/%s", user_socket_path, SOCKET_NAME);
    }
    else {
        char* homedir =  getenv ("HOME");
        if (homedir != NULL) {
            sprintf(socket_path, "%s/%s", homedir, SOCKET_NAME);
        }
        else {
            printf("ERROR: $HOME env. variable not set and no alt. socket path given.\n");
            exit(1);
        }
    }
}


bool verifierSendsOn(prover_request request) {
    int requestType = request.requestType;
    return (requestType == CMT_INPUT || requestType == CMT_Q0 || requestType == CMT_R || requestType == CMT_TAU || requestType == CMT_QI || requestType == CMT_MUXSEL);
}

bool verifierRecievesOn(prover_request request) {
    int requestType = request.requestType;
    return (requestType == CMT_OUTPUT || requestType == CMT_F012 || requestType == CMT_H);
}
