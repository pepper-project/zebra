# parsepws makefile
# (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

CMT_DIR := ../verifier/cmt_circuits
CIRCUIT_DIR := $(CMT_DIR)/circuit
PEPPER_DEPS := $(HOME)/pepper_deps

IFLAGS := -I$(CMT_DIR) -I$(CMT_DIR)/include -I$(PEPPER_DEPS)/include
IFLAGS += -I$(HOME)/toolchains/include -I$(IUS_HOME)/inca/include

CXXFLAGS := -m64 -pedantic -pedantic-errors -std=c++11 -Werror -Wall -Wextra -Wpointer-arith -Wcast-qual -Wformat=2 $(IFLAGS)
CFLAGS := -m64 -pedantic -pedantic-errors -std=gnu11 -Werror -Wall -Wextra -Wshadow -Wpointer-arith -Wcast-qual -Wformat=2 -Wstrict-prototypes -Wmissing-prototypes $(IFLAGS)

LDFLAGS += -L$(PEPPER_DEPS)/lib -Wl,-rpath,$(PEPPER_DEPS)/lib
LDFLAGS += -L$(HOME)/toolchains/lib -Wl,-rpath,$(HOME)/toolchains/lib
LDLIBS += -lgmp -lchacha -lrt

all: parsepws pwsrepeat

pwsrepeat: pwsrepeat.cpp cmtobjs
	$(CXX) $(CXXFLAGS) -o $@ $< $(CMT_DIR)/circuit/*.o $(CMT_DIR)/include/common/*.o $(CMT_DIR)/include/crypto/*.o $(LDFLAGS) $(LDLIBS)

parsepws: parsepws.cpp cmtobjs
	$(CXX) $(CXXFLAGS) -o $@ $< $(CMT_DIR)/circuit/*.o $(CMT_DIR)/include/common/*.o $(CMT_DIR)/include/crypto/*.o $(LDFLAGS) $(LDLIBS)

.PHONY: cmtobjs
cmtobjs:
	$(MAKE) -C $(CMT_DIR)

clean:
	rm -rf *.o parsepws pwsrepeat
	$(MAKE) -C $(CMT_DIR) clean
