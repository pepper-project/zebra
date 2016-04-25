#!/usr/bin/perl -w
#
# generate a one-layer testbench either for synthesis or simulation
#
# USAGE: ./layergen.pl [-s] [n]
#
# -s: generate verilog for simulation
#     (otherwise, emit synthesis mode)
#
#  n: log_2(width) of generated circuit
#
use strict;
use Cwd qw(abs_path);
use File::Basename qw(dirname);

my $localdir = dirname(abs_path($0));

my $mode = 0;
my $log2width = 1;
if (scalar @ARGV > 0) {
    foreach my $arg (@ARGV) {
        if ($arg =~ /-s/i) {
            $mode = 1;
        } elsif (int($arg)) {
            $log2width = int($arg);
        }
    }
}

my $headfile = $localdir . "/head.synth";
my $tailfile = $localdir . "/tail.synth";
if ($mode) {
    $headfile = $localdir . "/head.sim";
    $tailfile = $localdir . "/tail.sim";
}

sub printconns {
    my $name = shift @_;
    my $add = shift @_;
    my $log2width = shift @_;
    my $n = shift @_;

    print "localparam [" . ($log2width * $n - 1) . ":0] $name = {";
    my $first = 1;
    for (my $i = $n - 1; $i >= 0; $i--) {
        if ($first == 0) {
            print ", ";
        } else {
            $first = 0;
        }

        print $log2width . "'d" . (($i + $add) % $n);
    }
    print "};\n";
}

print `cat $headfile`;

my $n = 2 ** $log2width;
my $nm1 = $n - 1;
my $l2wm1 = $log2width - 1;
if ($mode == 0) {
    print <<END
    , input  [`F_NBITS-1:0] v_in [$nm1:0]
    , input  [`F_NBITS-1:0] tau

    , input                 comp_w0
    , input  [`F_NBITS-1:0] tau_w0
    , output [`F_NBITS-1:0] w0 [$l2wm1:0]
    , output                w0_ready_pulse
    , output                w0_ready

    , output                ready_pulse
    , output          [1:0] ready_code

    , output [`F_NBITS-1:0] buf_data [$log2width:0]
    );

`define PROVER_SYNTH_TEST_N $n
END
}

print "localparam ngates = $n;\n";
print "localparam ninputs = $n;\n";

print "localparam [`GATEFN_BITS*" . $n . "-1:0] gates_fn = {";
my $first = 1;
for (my $i = 1; $i <= $n; $i++) {
    if ($first == 0) {
        print ", ";
    } else {
        $first = 0;
    }
    if ($i % 2) {
        print "`GATEFN_MUL";
    } else {
        print "`GATEFN_ADD";
    }
}
print "};\n";

&printconns("gates_in0", 0, $log2width, $n);
&printconns("gates_in1", 1, $log2width, $n);

print `cat $tailfile`;
