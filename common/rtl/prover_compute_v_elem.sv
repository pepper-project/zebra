// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// given V(x,0,x) and V(x,1,x), compute elements for next round of sumcheck
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// For the Prover to evaluate H(0), H(1), H(2) for a given round of the
// sumcheck protocol at level i, it must generate new evaluations of
// the multilinear extension of V_{i+1} of the form V(0, ...), V(1, ...),
// and V(2, ...), where V is a b-r+1-variate polynomial on the rth round,
// where b is lg(G_{i+1}).
//
// After the Verifier sends a new random value t to the Prover, the latter
// must evaluate V(t) before continuing to the next round. This block also
// handles that evaluation.

`ifndef __module_prover_compute_v_elem
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
`include "field_multiplier.sv"
module prover_compute_v_elem
    ( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] v0
    , input  [`F_NBITS-1:0] v1
    , input  [`F_NBITS-1:0] tau
    , input  [`F_NBITS-1:0] m_tau_p1

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] vtau
    );

// ready wires
wire [1:0] mul_ready;
wire add_ready, add_ready_pulse;
wire all_mul_ready = &mul_ready;
reg all_mul_ready_dly;
wire add_en = all_mul_ready & ~all_mul_ready_dly;
assign ready = add_ready & all_mul_ready;
assign ready_pulse = add_ready_pulse;

// output wires for muls
wire [`F_NBITS-1:0] v0_mul_out, v1_mul_out;

// multiply v0 by m_tau_p1
field_multiplier imul0
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en)
    , .a            (m_tau_p1)
    , .b            (v0)
    , .ready_pulse  ()
    , .ready        (mul_ready[0])
    , .c            (v0_mul_out)
    );

field_multiplier imul1
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en)
    , .a            (tau)
    , .b            (v1)
    , .ready_pulse  ()
    , .ready        (mul_ready[1])
    , .c            (v1_mul_out)
    );

field_adder iadd
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (add_en)
    , .a            (v0_mul_out)
    , .b            (v1_mul_out)
    , .ready_pulse  (add_ready_pulse)
    , .ready        (add_ready)
    , .c            (vtau)
    );

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        all_mul_ready_dly <= 1;
    end else begin
        all_mul_ready_dly <= all_mul_ready;
    end
end

endmodule
`define __module_prover_compute_v_elem
`endif // __module_prover_compute_v_elem
