# zebra top-level Makefile
# (C) 2016 Riad S. Wahby <rsw@cs.nyu.edu>
#
# See README.md for licensing information

all:
	make -C verifier
	make -C pws2sv
	make -C pws2svg

clean:
	make -C verifier clean
	make -C pws2sv clean
	make -C pws2svg clean
	make -C icarus clean
