#!/usr/bin/perl -w
# pws2sv.pl <filename> [nreps] [-p]
# generate a cmt_top or cmt_top_pl module from the given pws file
# (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>
use strict;
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use File::Temp qw(tempfile);

sub max {
    my $in1 = shift @_;
    my $in2 = shift @_;

    if ($in1 > $in2) {
        return $in1;
    } else {
        return $in2;
    }
}

# shuf_plstages parameter - edit this if you'd like
my $shufpl = 2;

my $localdir = dirname(abs_path($0));

my $repeats = 1;
my $pwsfile = "";
my $pipeline = 0;
my $renumber = "";
if (scalar(@ARGV) < 1) {
    print "Usage: $0 <pwsfile> [optional arguments]\n";
    print "Optional arguments:\n";
    print " N      repeat pwsfile N times in parallel\n";
    print "-p      generate a pipelined computation\n";
    print "-m      when repeating a PWS file with muxes,\n";
    print "        renumber the mux control bits for each\n";
    print "        repetition. (Default: all repetitions\n";
    print "        use the same control bits as the original.\n";
    exit(-1);
} else {
    $pwsfile = abs_path(shift @ARGV);
    foreach my $arg (@ARGV) {
        if ($arg =~ /-p/i) {
            $pipeline = 1;
        } elsif ($arg =~ /-m/i) {
            $renumber = "-m";
        } else {
            $repeats = int($arg);
        }
    }

    if (! -f $pwsfile) {
        die "Could not open $pwsfile: file does not exist.";
    }
}

if (! -x "$localdir/parsepws" || ! -x "$localdir/pwsrepeat") {
    die "Please run `make` first to build the parsepws and pwsrepeat executables!";
}

$/ = "\0";
my @parsed;
if ($repeats > 1) {
    # create a tempfile
    my ($fh, $tfile) = tempfile();
    $tfile = abs_path($tfile);
    close($fh);

    # first call pwsrepeat
    system("$localdir/pwsrepeat $pwsfile $repeats $renumber > $tfile");
    if ($? == -1) {
        die "Failed to exec pwsrepeat: $!";
    }

    # now call parsefh on the result
    my $parsefh;
    open($parsefh, '-|', "$localdir/parsepws $tfile") or die "Failed to exec parsepws: $!";
    @parsed = <$parsefh>;
    close($parsefh);
    unlink($tfile);
} else {
    # no repeats necessary
    my $parsefh;
    open($parsefh, '-|', "$localdir/parsepws $pwsfile") or die "Failed to execute parsepws: $!";
    @parsed = <$parsefh>;
    close($parsefh);
}

chomp @parsed;

if (scalar(@parsed) < 2) {
    die("Error parsing circuit: expected at least one layer.\n\n***\n" . join("\n***\n", @parsed) . "\n***\n");
}

# number of layers
my $nlayers = 0;
if ($parsed[0] =~ /nlayers = (\d+);/) {
    $nlayers = $1;
} else {
    die("Error: couldn't parse nlayers.\n\n***\n" . join("\n***\n", @parsed) . "\n***\n");
}
if ($#parsed != $nlayers) {
    die("Error: got wrong number of layer defs.\n\n***\n" . join("\n***\n", @parsed) . "\n***\n");
}

my $nmuxsels = 0;
if ($parsed[0] =~ /nmuxsels = (\d+);/) {
    $nmuxsels = $1;
} else {
    die("Error: couldn't parse nmuxsels.\n\n***\n" . join("\n***\n", @parsed) . "\n***\n");
}

# width of the input layer
my $inwidth = 0;
if ($parsed[1] =~ /ninputs_\d+ = (\d+);/) {
    $inwidth = $1;
} else {
    die("Error: couldn't parse input width.\n\n***\n" . join("\n***\n", @parsed) . "\n***\n");
}

# width of the output layer
my $outwidth = 0;
if ($parsed[$#parsed] =~ /ngates_\d+ = (\d+);/) {
    $outwidth = $1;
} else {
    die("Error: couldn't parse output width.\n\n***\n" . join("\n***\n", @parsed) . "\n***\n");
}

my $maxwidth = max($inwidth, $outwidth);
for (my $i = 1; $i < $nlayers; $i++) {
    if ($parsed[$i] =~ /ngates_\d+ = (\d+);/) {
        $maxwidth = max($maxwidth, $1);
    } else {
        die("Error: couldn't parse layer $i width.\n\n***\n" . join("\n***\n", @parsed) . "\n***\n");
    }
}

if ($pipeline == 0) {

    print <<END;
// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// this is an automatically generated file. Edit at your own risk.
// source PWS file: $pwsfile

`ifndef __module_cmt_top
`include "simulator.v"
`include "field_arith_defs.v"
`include "gatefn_defs.v"
`include "layer_top.sv"
`include "verifier_interface_w0.sv"

// define these as macros so that cmt_top_test can invoke them
`define CMT_TOP_MAXWIDTH $maxwidth
`define CMT_TOP_NLAYERS $nlayers
`define CMT_TOP_INWIDTH $inwidth
`define CMT_TOP_OUTWIDTH $outwidth
`define CMT_TOP_NMUXSELS $nmuxsels
module cmt_top
    ( input                             clk
    , input                             rstb

    , input                      [31:0] id
    , input     [`CMT_TOP_NMUXSELS-1:0] mux_sel

    , input                             en_comp
    , input              [`F_NBITS-1:0] comp_in [`CMT_TOP_INWIDTH-1:0]
    , output                            comp_ready_pulse
    , output                            comp_ready
    , output             [`F_NBITS-1:0] comp_out [`CMT_TOP_OUTWIDTH-1:0]

    , input                             en_sumchk
    , output                            sumchk_ready_pulse
    , output                            sumchk_ready
    );

// *** definitions parsed from PWS file follow ***
END

    print join("\n", @parsed);
    print "// *** end definitions parsed from PWS file ***\n\n";

    my $nl1 = $nlayers - 1;
    print <<END;
// enable and ready signals for computation_layer
wire [nlayers-1:-1] en_layer_comp;
assign en_layer_comp[nlayers-1] = en_comp;
assign comp_ready_pulse = en_layer_comp[-1];
wire [nlayers-1:0] comp_layer_ready;
assign comp_ready = &(comp_layer_ready);

// enable and ready signals for prover_layer
wire [nlayers:0] en_layer_sumchk;
assign en_layer_sumchk[0] = en_sumchk;
assign sumchk_ready_pulse = en_layer_sumchk[nlayers];
wire [nlayers-1:0] sumchk_layer_ready;
assign sumchk_ready = &(sumchk_layer_ready);

// comp_in arrays have different widths for each layer
END

    for (my $i = 0; $i < $nlayers; $i++) {
        print "wire [`F_NBITS-1:0] comp_layer_in_$i [ninputs_$i-1:0];\n";
    }

    print <<END;
assign comp_layer_in_$nl1 = comp_in;

// w0 interconnect between layers
wire [`F_NBITS-1:0] tau_w0_out [nlayers:0];
assign tau_w0_out[nlayers] = {(`F_NBITS){1'b0}};
wire [nlayers:0] comp_w0_out;
assign comp_w0_out[nlayers] = 1'b0;
wire [nlayers:0] w0_ready_in;
wire [nlayers:0] w0_done_pulse_out;
assign w0_done_pulse_out[nlayers] = 1'b1;

// w0 arrays have different widths for each layer
END

    for (my $i = 0; $i < $nlayers; $i++) {
        print "localparam ngbits_$i = \$clog2(ngates_$i);\n";
        print "wire [`F_NBITS-1:0] w0_in_$i [ngbits_$i-1:0];\n";
    }

    print <<END;

// this is the block that retrieves w0 (aka q0) from the verifier
verifier_interface_w0
   #( .ngates       (ngates_0)
    ) iintfw0
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (comp_w0_out[0])
    , .id           (id)
    , .w0_ready     (w0_ready_in[0])
    , .w0           (w0_in_0)
    );
END

    for (my $i = 0; $i < $nlayers; $i++) {
        my $im1 = $i - 1;
        my $ip1 = $i + 1;

        # what do we call the computation output for this layer?
        my $compout;
        if ($i == 0) {
            $compout = "comp_out";
        } else {
            $compout = "comp_layer_in_$im1";
        }

        my $w0out;
        if ($i == $nlayers - 1) {
            $w0out = "";
        } else {
            $w0out = "w0_in_$ip1";
        }

        print <<END;

// this is layer $i
layer_top
   #( .ngates               (ngates_$i)
    , .ninputs              (ninputs_$i)
    , .nmuxsels             (nmuxsels)
    , .layer_num            ($i)
    , .gates_fn             (gates_fn_$i)
    , .gates_in0            (gates_in0_$i)
    , .gates_in1            (gates_in1_$i)
    , .gates_mux            (gates_mux_$i)
    , .shuf_plstages        ($shufpl)
    ) ilayer_$i
    ( .clk                  (clk)
    , .rstb                 (rstb)
    , .en_comp              (en_layer_comp[$i])
    , .comp_in              (comp_layer_in_$i)
    , .comp_out             ($compout)
    , .comp_ready_pulse     (en_layer_comp[$im1])
    , .comp_ready           (comp_layer_ready[$i])
    , .en_sumchk            (en_layer_sumchk[$i])
    , .id                   (id)
    , .mux_sel              (mux_sel)
    , .comp_w0_in           (comp_w0_out[$ip1])
    , .tau_w0_in            (tau_w0_out[$ip1])
    , .w0_out               ($w0out)
    , .w0_ready_out         (w0_ready_in[$ip1])
    , .comp_w0_out          (comp_w0_out[$i])
    , .tau_w0_out           (tau_w0_out[$i])
    , .w0_in                (w0_in_$i)
    , .w0_ready_in          (w0_ready_in[$i])
    , .w0_done_pulse_out    (w0_done_pulse_out[$i])
    , .w0_done_pulse_in     (w0_done_pulse_out[$ip1])
    , .sumchk_ready_pulse   (en_layer_sumchk[$ip1])
    , .sumchk_ready         (sumchk_layer_ready[$i])
    );
END
    }

    print <<END;

endmodule
`define __module_cmt_top
`endif // __module_cmt_top
END

} else {

    print <<END;
// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// this is an automatically generated file. Edit at your own risk.
// source PWS file: $pwsfile

`ifndef __module_cmt_top_pl
`include "simulator.v"
`include "field_arith_defs.v"
`include "gatefn_defs.v"
`include "layer_top_pl.sv"
`include "verifier_interface_w0.sv"

// define these as macros so that cmt_top_test can invoke them
`define CMT_TOP_PL_MAXWIDTH $maxwidth
`define CMT_TOP_PL_NLAYERS $nlayers
`define CMT_TOP_PL_INWIDTH $inwidth
`define CMT_TOP_PL_OUTWIDTH $outwidth
`define CMT_TOP_PL_NMUXSELS $nmuxsels
module cmt_top_pl
    ( input                             clk
    , input                             rstb

    , input                             en
    , input                             comp_new
    , output                            comp_done

    , input                      [31:0] id_in
    , input              [`F_NBITS-1:0] comp_in [`CMT_TOP_PL_INWIDTH-1:0]
    , input  [`CMT_TOP_PL_NMUXSELS-1:0] mux_sel

    , output                     [31:0] id_out
    , output             [`F_NBITS-1:0] comp_out [`CMT_TOP_PL_OUTWIDTH-1:0]

    , output                            ready_pulse
    , output                            ready
    , output                            idle
    );

// *** definitions parsed from PWS file follow ***
END

    print join("\n", @parsed);
    print "// *** end definitions parsed from PWS file ***\n\n";

    my $nl1 = $nlayers - 1;
    print <<END;
// en pulse
reg en_dly;
wire start = en & ~en_dly;

// ready signals
wire [nlayers-1:0] comp_ready;
wire [nlayers-1:0] sumchk_ready;
assign ready = (&(comp_ready)) & (&(sumchk_ready));
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

// each layer is working on a different ID in the pipelined computation
wire [31:0] id_c_lay [nlayers-1:-1];
wire [31:0] id_p_lay [nlayers:0];
assign id_c_lay[nlayers-1] = id_in;
assign id_out = id_c_lay[-1];
assign id_p_lay[0] = id_c_lay[-1];

// pipeline status shift register is distributed among layer_top_pl instances
wire [nlayers-1:-1] comp_en_in;
assign comp_en_in[nlayers-1] = comp_new;
wire [nlayers:0] sumchk_en_in;
assign sumchk_en_in[0] = comp_en_in[-1];
assign comp_done = comp_en_in[-1];

// cbuf_en_in[i] indicates that a computation or proof for
// layer 0 <= j <= i-1 is in progress (thus the layer should
// continue advancing the cbuf)
wire [nlayers-1:0] active_next;
assign idle = ~(|active_next);

// comp_in arrays have different widths for each layer, so no 2d arrays
END

    for (my $i = 0; $i < $nlayers; $i++) {
        print "wire [`F_NBITS-1:0] comp_layer_in_$i [ninputs_$i-1:0];\n";
    }

    print <<END;
assign comp_layer_in_$nl1 = comp_in;

// w0 interconnect between layers
wire [`F_NBITS-1:0] tau_w0_out [nlayers:0];
assign tau_w0_out[nlayers] = {(`F_NBITS){1'b0}};
wire [nlayers:0] comp_w0_out;
assign comp_w0_out[nlayers] = 1'b0;
wire [nlayers:0] w0_ready_in;
wire [nlayers:0] w0_done_pulse_out;
assign w0_done_pulse_out[nlayers] = 1'b1;

// w0 arrays have different widths for each layer, so no 2d arrays
END

    for (my $i = 0; $i < $nlayers; $i++) {
        print "localparam ngbits_$i = \$clog2(ngates_$i);\n";
        print "wire [`F_NBITS-1:0] w0_in_$i [ngbits_$i-1:0];\n";
    }

    print <<END;

// this is the block that retrieves w0 (aka q0) from the verifier
verifier_interface_w0
   #( .ngates       (ngates_0)
    ) iintfw0
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (comp_w0_out[0])
    , .id           (id_p_lay[1])
    , .w0_ready     (w0_ready_in[0])
    , .w0           (w0_in_0)
    );
END

    for (my $i = 0; $i < $nlayers; $i++) {
        my $im1 = $i - 1;
        my $ip1 = $i + 1;

        # what do we call the computation output for this layer?
        my ($compout);
        if ($i == 0) {
            $compout = "comp_out";
        } else {
            $compout = "comp_layer_in_$im1";
        }

        my $w0out;
        if ($i == $nlayers - 1) {
            $w0out = "";
        } else {
            $w0out = "w0_in_$ip1";
        }

        print <<END;

// this is layer $i
layer_top_pl
   #( .ngates               (ngates_$i)
    , .ninputs              (ninputs_$i)
    , .nmuxsels             (nmuxsels)
    , .layer_num            ($i)
    , .gates_fn             (gates_fn_$i)
    , .gates_in0            (gates_in0_$i)
    , .gates_in1            (gates_in1_$i)
    , .gates_mux            (gates_mux_$i)
    , .shuf_plstages        ($shufpl)
    ) ilayer_$i
    ( .clk                  (clk)
    , .rstb                 (rstb)
    , .en                   (start)
    , .comp_en_in           (comp_en_in[$i])
    , .comp_en_out          (comp_en_in[$im1])
    , .sumchk_en_in         (sumchk_en_in[$i])
    , .sumchk_en_out        (sumchk_en_in[$ip1])
    , .mux_sel              (mux_sel)
    , .active_next          (active_next[$i])
    , .comp_in              (comp_layer_in_$i)
    , .comp_out             ($compout)
    , .comp_ready_pulse     ()
    , .comp_ready           (comp_ready[$i])
    , .id_c_in              (id_c_lay[$i])
    , .id_c_out             (id_c_lay[$im1])
    , .id_p_in              (id_p_lay[$i])
    , .id_p_out             (id_p_lay[$ip1])
    , .comp_w0_in           (comp_w0_out[$ip1])
    , .tau_w0_in            (tau_w0_out[$ip1])
    , .w0_out               ($w0out)
    , .w0_ready_out         (w0_ready_in[$ip1])
    , .comp_w0_out          (comp_w0_out[$i])
    , .tau_w0_out           (tau_w0_out[$i])
    , .w0_in                (w0_in_$i)
    , .w0_ready_in          (w0_ready_in[$i])
    , .w0_done_pulse_out    (w0_done_pulse_out[$i])
    , .w0_done_pulse_in     (w0_done_pulse_out[$ip1])
    , .sumchk_ready_pulse   ()
    , .sumchk_ready         (sumchk_ready[$i])
    );
END
    }

    print <<END;

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1;
        ready_dly <= 1;
    end else begin
        en_dly <= en;
        ready_dly <= ready;
    end
end

endmodule
`define __module_cmt_top_pl
`endif // __module_cmt_top_pl
END

}
