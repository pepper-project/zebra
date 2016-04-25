# icarus/Makefile
# (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

VPIMODULES = arith hello sendrcv vpiserver
MODULES = arith sendrcv
SIMULATOR = vvp

VERBOSE ?= 1
ifeq ($(VERBOSE),1)
	SIMULATOR += -v
endif

.PHONY: clean links

all: $(MODULES:%=sim_%)

links:
	make -C vpi links
	make -C rtl links

sim_%:
	$(eval TARG := $(@:sim_%=%))
	make -C vpi $(VPIMODULES:=.vpi)
	make -C rtl $(TARG).vvp NCOMPS=$(NCOMPS)
	$(SIMULATOR) -Mvpi $(VPIMODULES:%=-m%) rtl/$(TARG).vvp -fst

include ../pws2sv/pws_target.makefrag

clean:
	make -C vpi clean
	make -C rtl clean
	rm -f *.vcd *.fst *.fst.hier arith_log.txt
	rm -f rtl/cmt_top.sv rtl/cmt_top_pl.sv rtl/layergen.sv rtl/prover_synth_test.sv
