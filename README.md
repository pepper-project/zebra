# Zebra

This repository contains an implementation of Verifiable ASICs
[[WHGsW16](https://eprint.iacr.org/2015/1243)].

This release includes the software Verifier implementation and the hardware
Prover implementation. We are still cleaning up the hardware Verifier
implementation, and we will release it asap.

This code has been built and tested under Linux. It may be portable to other
operating systems; if you are having problems, please feel free to open
an issue.

# Building

## Prerequisites

You should install all of the following using your distribution's package
manager.

- cmake
- gcc, g++, and other build tools (e.g., `build-essential` under Debian)
- libgmp 6.x
- make
- perl 5.x
- python 2.7

## Building MPFQ

You'll need to install libmpfq. We assume that you're going to build it under `~/toolchains`.

    mkdir -p ~/toolchains/src
    cd ~/toolchains/src
    wget https://github.com/pepper-project/thirdparty/blob/master/mpfq-1.1.tar.bz2?raw=true -O mpfq-1.1.tar.bz2
    tar xjvf mpfq-1.1.tar.bz2  
    cd mpfq-1.1/src  
    mkdir build  
    cd build  
    cmake .. -DCMAKE_INSTALL_PREFIX=$HOME/toolchains  
    make  
    make install  

## Building chacha

You'll also need chacha. What's below assumes you're on a 64-bit machine.

    mkdir -p ~/toolchains/src
    cd ~/toolchains/src
    wget https://github.com/pepper-project/thirdparty/blob/master/chacha-fast.tar.gz?raw=true -O chacha.tar.gz
    tar -xvzf chacha.tar.gz
    cd chacha-fast
    make PREFIX=$HOME/toolchains
    make PREFIX=$HOME/toolchains install

## Building Icarus

Finally, you'll need a development version of [Icarus
Verilog](https://github.com/steveicarus/iverilog) installed. (You need
a dev version because the current stable release does not support some
features that we need).

We've tested with git commit 64b72cf7e1eaf6d3de555ffbb319417f8cca97cf,
with Icarus installed system-wide.

    mkdir -p ~/toolchains/src
    cd ~/toolchains/src
    git clone https://github.com/steveicarus/iverilog
    cd iverilog
    git checkout 64b72cf7e1eaf6d3de555ffbb319417f8cca97cf    # optional, probably...
    ./configure --prefix=/usr/local                          # installing system-wide
    make
    make check                                               # optional
    sudo make install

## Almost there...

Finally, you're ready to build the support libraries for Zebra. For this,
just `make` in the base directory of your Zebra checkout.

# Simulating a Zebra chip

Finally, we're ready to simulate the execution of a Zebra computation.

## Defining a computation: prover worksheets

The Zebra simulator takes as input *prover worksheet* or *PWS* files.
The `pws/` subdirectory contains some examples of PWS files, as well as a couple
scripts to generate PWS files for specific computations.

In the future we will add more complete documentation of PWS syntax here.

## Running a computation

There are two entities involved in executing a computation: the prover and
the verifier. When simulating a Zebra chip, each entity runs on a separate
process. This is easiest if you use two terminal windows, two virtual windows
inside GNU screen, or the moral equivalent.

It's probably simplest to walk through an example. Let's assume we're going
to run the `simple4.pws` computation from the `pws/` subdirectory.

### Example: `simple4.pws`

#### Verifier

You will run the verifier process from the `verifier/` subdirectory. So:

    cd verifier
    make NREPS=4 pws_simple4

Note that the Makefile assumes that the input file lives in the `pws/`
directory; all you need to do is prepend `pws_` to the name of the worksheet
(and leave off the `.pws` suffix) and you're ready to go.

The `NREPS` option specifies how many repetitions of the computation should
be executed in parallel. If you don't specify it, the default is 1. In the
above example, we're repeating the computation 4 times in parallel.

The above command won't return; you can interrupt it with ctrl-c after the
prover has finished executing.

#### Prover

You will run the prover process from the `icarus/` subdirectory. In another
terminal window:

    cd icarus
    make PIPELINE=0 NREPS=4 clean pws_simple4 sim_cmt_top_test

`PIPELINE=0` specifies that we are not running a pipelined prover (more on
this below). `NREPS` must match the argument given to the verifier.
`pws_simple4`, as above, specifies to use `pws/simple4.pws` as input.
Finally, the target `sim_cmt_top_test` executes the top-level testbench.

### Running a computation with pipelining

It's also possible to run a pipelined computation, where multiple layers
of the prover execute in parallel. Once again, we'll be running the prover
and verifier in separate terminals, and we'll run `simple4.pws`.

#### Verifier

    cd verifier
    make NREPS=4 NCOMPS=8 pws_simple4

Notice we've added a new option, `NCOMPS`. This tells the verifier how many
computations the prover will be executing in a pipeline.

#### Prover

    cd icarus
    make PIPELINE=1 NREPS=4 NCOMPS=8 clean pws_simple4 sim_cmt_top_pl_test

This time, we've set `PIPELINE=1` and `NCOMPS=8`. Also note that when
`PIPELINE=1`, the simulation target should be `sim_cmt_top_pl_test` rather
than `sim_cmt_top_test`!

# Copying

This code is Copyright © 2015-16 Riad S. Wahby, Max Howald, and other members
of the Pepper Project.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program. If not, see http://www.gnu.org/licenses/.
