#include "verifier.h"

#include <circuit/pws_circuit_parser.h>
#include <circuit/pws_circuit.h>
#include <gmp.h>
#include <common/math.h>
#include <common/poly_utils.h>

#include <cstdlib>

#include <vector>

extern mpz_t mpz_buf[];

using namespace std;

int main (int argc, char* argv[]) {

    if (argc < 3) {
        cout << "usage: " << argv[0] << " <pwsfile>  <num instances>" << endl;
        exit(1);
    }

    mpz_t prime;
    mpz_init_set_ui(prime, 1);
    mpz_mul_2exp(prime, prime, PRIMEBITS);
    mpz_sub_ui(prime, prime, PRIMEDELTA);

    PWSCircuitParser parser(prime);
    PWSCircuit c(parser);

#ifdef DEBUG
    cout << "==== Constructing Circuit ====" << endl;
#endif
    parser.parse(argv[1]);
    c.construct();
#ifdef DEBUG
    cout << "==== Construction Complete ====" << endl;

    parser.printCircuitDescription();
#endif
    parser.printCircuitStats();

    if (argc > 3 && argv[3][0] == 'x') {
        exit(0);
    }

    int numInstances = atoi(argv[2]);

    VerifierPrecomputation* precomp = new VerifierPrecomputation[numInstances];


    int numMuxBits = parser.largestMuxBitIndex + 1;
    vector<bool> muxBits(numMuxBits);
    for (int i = 0; i < numMuxBits; i++) {
        muxBits[i] = i % 2;
    }

    //to pass muxbits to a c function
    //(vector<bool> doesn't implement data() for doing this easily...)
    bool* muxArr = new bool[numMuxBits];
    copy(muxBits.begin(), muxBits.end(), muxArr);


    //precompute user-specified number of computation instances.
    for (int i = 0; i < numInstances; i++) {
        precomp[i].init(&c);
        precomp[i].flipAllCoins();
        precomp[i].computeAddMul(muxBits);
    }

    VerifierCompState verState[PIPELINE_DEPTH];
    for (int i = 0; i < PIPELINE_DEPTH; i++) {
        init_cmt_io(i, c.maxWidth(), c.depth());
    }

    initConnection();

    while(1) {
        int rcv_sock = accept(listen_sock, NULL, 0);
        if (rcv_sock == -1)
            perror("accept");

        FILE* fp = fdopen(rcv_sock, "r");

        prover_request request = recieveHeader(fp);

        if (request.requestType == CMT_MUXSEL) {
            sendHeader(request, rcv_sock);
            sendMuxBits(muxArr, numMuxBits, rcv_sock);
            fclose(fp);
            close(rcv_sock);
            continue;
        }

        if (request.id >= numInstances) {
            cout << "ERROR: requested computation id for computation that has not been precomputed. exiting" << endl;
            exit(1);
        }

        handle(request, fp, rcv_sock, precomp, verState);

        fclose(fp);
        close(rcv_sock);
    }


}


void handle(prover_request request, FILE* readfp, int socket, VerifierPrecomputation* precomp, VerifierCompState* verState) {

    int comp_state_id = request.id % PIPELINE_DEPTH;

    if (verifierSendsOn(request)) {

        switch (request.requestType) {
        case CMT_INPUT:
            verState[comp_state_id].init(&precomp[request.id], comp_state_id);
            verState[comp_state_id].generateInputs(request);
            break;
        case CMT_Q0:
            verState[comp_state_id].sendQ0(request);
            break;
        case CMT_R:
            verState[comp_state_id].sendNextR(request);
            break;
        case CMT_TAU:
            verState[comp_state_id].sendNextT(request);
            break;
        case CMT_QI:
            verState[comp_state_id].sendNextQI(request);
            break;
        }
        put_cmt_io(mpz_buf, request);
        sendHeader(request, socket);
        sendMPZ(request.howMany, socket);
    }

    else if (verifierRecievesOn(request)) {

        recieveMPZ(request.howMany, readfp);
        put_cmt_io(mpz_buf, request);

        switch (request.requestType) {
        case CMT_OUTPUT:
            verState[comp_state_id].checkOutputs(request);
            break;
        case CMT_F012:
            verState[comp_state_id].checkF012(request);
            break;
        case CMT_H:
            verState[comp_state_id].checkH(request);
            break;
        }

    }

    else
        cout << "ERROR: Invalid requestType in header" << endl;
}




void initConnection() {
    for (int i = 0; i < MPZ_BUF_LEN; i++)
        mpz_init(mpz_buf[i]);


    listen_sock = socket(AF_UNIX, SOCK_STREAM, 0);
    if (listen_sock < 0) {
        perror("opening stream socket");
        exit(1);
    }
    char socket_path[1000];
    getSocketPath(socket_path);

    unlink(socket_path);
    server.sun_family = AF_UNIX;
    strcpy(server.sun_path, socket_path);
    if (bind(listen_sock, (struct sockaddr *) &server, sizeof(struct sockaddr_un))) {
        perror("binding stream socket");
        exit(1);
    }

    listen(listen_sock, MAX_NUM_CONNECTIONS);

}
