// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// compute element of w0 for next round of sumcheck from tau
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// After the sumcheck is finished, V sends one more value, tau.
// P must evaluate gamma(tau) in order to get w0 for the next round,
// where gamma(t) = (w2 - w1)*t + w1. This module computes one element of the
// vector w0.

`ifndef __module_prover_compute_w0_elem
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
`include "field_multiplier.sv"
module prover_compute_w0_elem
    ( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] w1
    , input  [`F_NBITS-1:0] w2_m_w1
    , input  [`F_NBITS-1:0] tau

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] w0
    );

wire mul_ready_pulse;
wire mul_ready;
wire [`F_NBITS-1:0] tau_w2_m_w1;
field_multiplier imul
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en)
    , .a            (w2_m_w1)
    , .b            (tau)
    , .ready_pulse  (mul_ready_pulse)
    , .ready        (mul_ready)
    , .c            (tau_w2_m_w1)
    );

wire add_ready;
assign ready = add_ready & mul_ready;
field_adder iadd
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (mul_ready_pulse)
    , .a            (tau_w2_m_w1)
    , .b            (w1)
    , .ready_pulse  (ready_pulse)
    , .ready        (add_ready)
    , .c            (w0)
    );

endmodule
`define __module_prover_compute_w0_elem
`endif // __module_prover_compute_w0_elem
