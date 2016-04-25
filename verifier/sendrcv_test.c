//A simple program to send and recieve some mpz's from the sim.

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#include <gmp.h>

#define SOCKET_PATH "/tmp/a_socket"

int main(int argc, char* argv[]) {
	
    if (argc < 4) {
        printf("usage: %s <num_to_send> <num_to_recieve> <num_rounds>\n", argv[0]);
        exit(1);
    }
 
    int num_to_send = atoi(argv[1]);
    int num_to_recieve = atoi(argv[2]);
    int num_rounds = atoi(argv[3]);

    char c;
    char buf[1024];

    int sock;
    struct sockaddr_un server;
    server.sun_family = AF_UNIX;
    strcpy(server.sun_path, SOCKET_PATH);

    unsigned long int seed = 12345;
    gmp_randstate_t r_state;
    gmp_randinit_default (r_state);
    gmp_randseed_ui(r_state, seed);
		
    mpz_t to_send[num_to_send];
    mpz_t to_recieve[num_to_recieve];
		
    for (int i = 0; i < num_to_send; i++)
        mpz_init(to_send[i]);
    for (int i = 0; i < num_to_recieve; i++)
        mpz_init(to_recieve[i]);
		
  
    for (int i = 0; i < num_rounds; i++) {

			
        //connect and send some input to the sim.

        sock = socket(AF_UNIX, SOCK_STREAM, 0);
        if (sock < 0) {
            perror("opening stream socket");
            exit(1);
        }

        if (connect(sock, (struct sockaddr *) &server, sizeof(struct sockaddr_un)) < 0) {
            close(sock);
            perror("connecting stream socket");
            exit(1);
        }	

        printf("sending: ");
        for (int j = 0; j < num_to_send; j++) {
            mpz_rrandomb(to_send[j],r_state,14);
            bzero(buf, sizeof(buf));
            gmp_sprintf(buf, "%Zd,", to_send[j]);
            printf("%s ", buf);

            if (write(sock, buf, strlen(buf)) < 0)
                perror("writing on stream socket");
        }
        printf("\n");
        close(sock);

        //connect and recieve some output from the sim.


        sock = socket(AF_UNIX, SOCK_STREAM, 0);
        if (sock < 0) {
            perror("opening stream socket");
            exit(1);
        }

        if (connect(sock, (struct sockaddr *) &server, sizeof(struct sockaddr_un)) < 0) {
            close(sock);
            perror("connecting stream socket");
            exit(1);
        }	
		
        FILE* fp = fdopen(sock, "r");
      
        bzero(buf, sizeof(buf));
        for (int k = 0; (c = fgetc(fp)) != EOF; k++) {
            buf[k] = c;

            if (c == ',') {
                buf[k] = 0;
                break;
            }
        }
        gmp_printf("\nrecieved header: %s\n", buf);
      
        for (int j = 0; j < num_to_recieve; j++) {
            bzero(buf, sizeof(buf));
            for (int k = 0; (c = fgetc(fp)) != EOF; k++) {
            
                buf[k] = c;
                if (c == ',') {
                    buf[k] = 0;
                    break;
                }
            }
            gmp_sscanf(buf, "%Zd", to_recieve[j]);
        }

        gmp_printf("recieved: ");
        for (int j = 0; j < num_to_recieve; j++) {
            gmp_printf("%Zd, ", to_recieve[j]);
        }
        gmp_printf("\n");

	fclose(fp);
        close(sock);


    }


}

