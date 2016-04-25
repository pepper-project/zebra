

CXX := g++ -O2
IFLAGS := -I./include -I ~/pepper_deps/include
IFLAGS += -I$(HOME)/toolchains/include -I$(IUS_HOME)/inca/include

LDFLAGS := -L$(HOME)/pepper_deps/lib -Wl,-rpath,$(HOME)/pepper_deps/lib
LDFLAGS += -L$(HOME)/toolchains/lib -Wl,-rpath,$(HOME)/toolchains/lib
LDLIBS := -lgmp -lchacha -lrt

.PHONY: ckts
ckts:
	make -C circuit
	make -C include/common
	make -C include/crypto

pws_circuit_test: pws_circuit_test.cpp ckts
	$(CXX)  $(IFLAGS) $< circuit/*.o include/common/*.o include/crypto/*.o $(LDFLAGS) -o pws_circuit_test $(LDLIBS)

clean:
	make -C circuit clean
	make -C include/common clean
	make -C include/crypto clean
	rm -rf pws_circuit_test
