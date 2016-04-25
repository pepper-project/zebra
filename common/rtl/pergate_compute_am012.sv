// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// compute this gate's add~ or mul~ contribution to V(0), V(1), and V(2)
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// Each gate (with lgG-bit label g) contributes a term of the form
//
//     lgG - 1
//      _____
//  V    | |   X     (n   )
//   g   | |    g[k]   k+1
//      k = 0
//
// to the evaluation of V(n_1, n_2, ..., n_(lgG)), where
//   X_1 (n) = n
//   X_0 (n) = 1 - n
//
// During each round of the sumcheck protocol, the Prover is asked
// to evaluate V(..., 0, ...), V(..., 1, ...), and V(..., 2, ...).
//

`ifndef __module_pergate_compute_am012
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_negate_or_double.sv"
module pergate_compute_am012
    ( input                 clk
    , input                 rstb

    , input                 en
    , input                 gate_id_bit
    , input  [`F_NBITS-1:0] addmul_in

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] addmul [2:0]
    );

assign addmul[0] = gate_id_bit ? 0 : addmul_in;
assign addmul[1] = gate_id_bit ? addmul_in : 0;

`ifndef USE_FJM1
    wire double_en = gate_id_bit;
`else
    wire double_en = ~gate_id_bit;
`endif

field_negate_or_double inord
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en)
    , .double       (double_en)
    , .a            (addmul_in)
    , .ready_pulse  (ready_pulse)
    , .ready        (ready)
    , .c            (addmul[2])
    );

endmodule
`define __module_pergate_compute_am012
`endif // __module_pergate_compute_am012
