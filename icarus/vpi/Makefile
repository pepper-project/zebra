# icarus/vpi/Makefile
# (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

MODULES = hello arith sendrcv vpiserver
OBJS = util sendrcv_typechecker vpi_util


# add -lgmp or whatever below
VPICC := gcc -std=gnu99
VPICXX := g++ -std=c++11
VPICCFLAGS := $(shell iverilog-vpi --cflags) -I../../verifier -m64 -pedantic -pedantic-errors -Werror -Wall -Wshadow -Wpointer-arith -Wcast-qual -Wformat=2 -Wno-unused-function
VPILDFLAGS := $(shell iverilog-vpi --ldflags) -L../../verifier -Wl,-rpath,$(shell readlink -f ../../verifier)
VPILDLIBS := $(shell iverilog-vpi --ldlibs) -lgmp -lcmtprecomp

.PHONY: clean links cmtprecomp

all: $(MODULES:=.vpi)

cmtprecomp:
	make -C ../../verifier cmt_circuits libcmtprecomp.so

links:
	find . -mindepth 1 -maxdepth 1 -type l -print0 | xargs -0 rm
	find ../../common/vpi -type f -print0 | xargs -0 ln -t . -s

%.o: %.c %.h
	$(VPICC) $(VPICCFLAGS) -c $< -o $@

%.o: %.cpp %.h
	$(VPICXX) $(VPICCFLAGS) -c $< -o $@

%.vpi: %.o $(OBJS:=.o) cmtprecomp
	$(VPICC) -o $@ $(VPILDFLAGS) $< $(OBJS:=.o) $(VPILDLIBS)

clean:
	rm -f *.o *.vpi
