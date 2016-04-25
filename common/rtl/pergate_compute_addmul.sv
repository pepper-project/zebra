// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// For a single gate in level i, compute the piece of
//    add_i or mul_i that depends on the random point tau
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// We precompute, for a gate with lgG-bit label g,
//
// lgG - 1
//  _____
//   | |   X     (tau   )
//   | |    g[k]     k+1
//  k = 0
//
// where
//   X_1 (n) = n
//   X_0 (n) = 1 - n
//
// and tau_i are the elements of the lgG-length vector of random
// field elements supplied by V.
//
// Thereafter over the course of the sumcheck, P continues multiplying
// by random elements supplied by the Verifier.

`ifndef __module_pergate_compute_addmul
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_multiplier.sv"
module pergate_compute_addmul
    ( input                 clk
    , input                 rstb

    , input                 en
    , input                 restart
    , input                 gate_id_bit
    , input  [`F_NBITS-1:0] tau
    , input  [`F_NBITS-1:0] m_tau_p1

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] addmul
    );

// mux based on the current bit of the gate_id register
wire [`F_NBITS-1:0] am_select = restart ? 1 : addmul;
wire [`F_NBITS-1:0] tau_select = gate_id_bit ? tau : m_tau_p1;

field_multiplier imul
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en)
    , .a            (am_select)
    , .b            (tau_select)
    , .ready_pulse  (ready_pulse)
    , .ready        (ready)
    , .c            (addmul)
    );

endmodule
`define __module_pergate_compute_addmul
`endif // __module_pergate_compute_addmul
