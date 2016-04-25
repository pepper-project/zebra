CFLAGS := -fPIC -Og -g -m64 -pedantic -pedantic-errors -std=gnu99 -Werror -Wall -Wextra -Wshadow -Wpointer-arith -Wcast-qual -Wformat=2 -Wmissing-prototypes
CXXFLAGS :=  -fPIC -Og -g -m64 -pedantic -pedantic-errors -std=c++11 -Wall -Wextra -Wpointer-arith -Wcast-qual -Wformat=2 -Wno-vla -Werror

IFLAGS := -I./cmt_circuits/include -I./cmt_circuits/ -isystem $(HOME)/pepper_deps/include
IFLAGS += -isystem $(HOME)/toolchains/include -isystem $(IUS_HOME)/inca/include


LDFLAGS := -L$(HOME)/pepper_deps/lib -Wl,-rpath,$(HOME)/pepper_deps/lib
LDFLAGS += -L$(HOME)/toolchains/lib -Wl,-rpath,$(HOME)/toolchains/lib
LDLIBS_NOMPFQ := -lgmp -lchacha -lrt
LDLIBS := $(LDLIBS_NOMPFQ) -lmpfq_gfp

CC := gcc
CXX := g++

OBJS = util verifier_precomp verifier_comp_state

all: cmt_circuits sendrcv_test verifier precompute

.PHONY: cmt_circuits
cmt_circuits:
	$(MAKE) -C cmt_circuits

sendrcv_test: sendrcv_test.c
	$(CC) $(CFLAGS) $(IFLAGS) sendrcv_test.c $(LDFLAGS) -o sendrcv_test $(LDLIBS)

%.o: %.cpp %.h
	$(CXX) $(CXXFLAGS) $(IFLAGS) -c $<

%.o: %.c %.h
	$(CC) $(CFLAGS) $(IFLAGS) -c $<

verifier : verifier.cpp verifier.h $(OBJS:=.o)
	$(CXX) $(CXXFLAGS) $(IFLAGS) $<  $(OBJS:=.o) cmt_circuits/circuit/*.o cmt_circuits/include/common/*.o cmt_circuits/include/crypto/*.o $(LDFLAGS) -o $@ $(LDLIBS)

precompute : precompute.cpp precompute.h libcmtprecomp.so $(OBJS:=.o)
	$(CXX) $(CXXFLAGS) $(IFLAGS) $< -L. -Wl,-rpath,$(shell pwd) $(LDFLAGS) -o $@ -lcmtprecomp -lgmp

libcmtprecomp.so : cmtprecomp.cpp cmtprecomp_private.h cmtprecomp.h $(OBJS:=.o)
	$(CXX) $(CXXFLAGS) $(IFLAGS) $<  $(filter-out verifier_comp_state.o,$(OBJS:=.o)) cmt_circuits/circuit/*.o cmt_circuits/include/common/*.o cmt_circuits/include/crypto/*.o $(LDFLAGS) -flto -shared -Wl,-soname,$@ -o $@ $(LDLIBS_NOMPFQ)

MUXRENUM ?= 0
NREPS ?= 1
NCOMPS ?= 1
PLFLAG :=
ifeq ($(MUXRENUM),1)
	PLFLAG := -m
endif
pws_%: ../pws/%.pws cmt_circuits verifier
	make -C ../pws2sv
ifneq ($(NREPS),1)
	../pws2sv/pwsrepeat $< $(NREPS) $(PLFLAG) > ./tmp.pws
else
	cp $< ./tmp.pws
endif
	./verifier ./tmp.pws $(NCOMPS)

clean:
	rm -rf *.o sendrcv_test verifier tmp.pws precompute libcmtprecomp.so
	$(MAKE) -C cmt_circuits clean
