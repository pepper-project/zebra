// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// given f_j(0), f_j(1), and f_j(-1), compute coefficients of 2nd degree polynomial f_j
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// After each round of the sumcheck protocol, P sends three values to V.
// (In Allspice, these are f_j(0), f_j(1), and f_j(2).) V checks that
// f_j(0)+f_j(1) == f_{j-1}(tau), and then computes f_j(tau) by interpolating
// f_j from the three points in question.
//
// In the best case, this interpolation takes 5 or 6 field arithmetic operations
// (at least one of which is a multiplication). On the other hand, if P computes
// the coefficients for V, then V must compute f_j(0)+f_j(1) as follows:
//   f_j = c2 * x^2 + c1 * x + c0
//   => f_j(0) = c0
//   => f_j(1) = c0 + c1 + c2
// This takes V 3 adds rather than 1, but saves V several adds and multiplies.
//
// Another optimization is that P can compute f_j(-1) rather than f_j(2). This
// makes interpolating c1 and c2 easier:
//
// Let f0 = f_j(0), f1 = f_j(1), f_2 = f_j(2), and fm1 = f_j(-1).
//
// With f_j(2):
//
// c0 = f0
// a = (f2 - f0) / 2        (== 2 * c2 + c1)
// b = f1 - f0              (== c2 + c1)
// c2 = a - b
// c1 = 2*b - a
//
// In total, this requires one doubling, 4 subtracts, and one multiplication.
// (Doubling takes one add; subtraction takes two adds.)
//
// With f_j(-1):
//
// c0 = f0
// c2 = (fm1 + f1) / 2 - f0
// c1 = (f1 - fm1) / 2
//
// In total this requires one add, two subtracts, and two multiplications.
//
// If multiplication is substantially more than twice the cost of addition,
// the f2 method is better. If multiplication and addition are closer in cost,
// the fm1 method is better.

// NOTE this version is optimized for speed, NOT for space.
// This should not be used for the Verifier!

`ifndef __module_prover_compute_c012_fm1
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
`include "field_multiplier.sv"
`include "field_negate.sv"
`include "field_subtract.sv"
module prover_compute_c012_fm1
    ( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] fj [2:0]    // fj[2] = f_j(-1), fj[1] = f_j(1), fj[0] = f_j(0)

    , output                ready_pulse
    , output                ready

    , output [`F_NBITS-1:0] c [2:0]
    );

// enable pulse
reg en_dly;
wire start = en & ~en_dly;

// control for field arith gates
reg add_sel;
wire add_ready, add_ready_pulse;
wire sub_ready, sub_ready_pulse;
wire neg_ready;
wire [1:0] mul_ready;
wire mul_ready_pulse;

// connect outputs;
reg [`F_NBITS-1:0] c0_reg;
wire [`F_NBITS-1:0] mul_out [1:0];
wire [`F_NBITS-1:0] add_out;
assign c[0] = c0_reg;
assign c[1] = mul_out[0];
assign c[2] = add_out;

// ready signals for c1 and c2
wire c1_ready = sub_ready & mul_ready[0];
wire c2_ready = add_ready & neg_ready & mul_ready[1];
assign ready = c1_ready & c2_ready;
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

// *** Compute c2 ***
wire [`F_NBITS-1:0] m_f0;
field_negate ineg
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (start)
    , .a            (fj[0])
    , .ready_pulse  ()
    , .ready        (neg_ready)
    , .c            (m_f0)
    );

wire [`F_NBITS-1:0] addend_a = add_sel ? mul_out[1] : fj[2];
wire [`F_NBITS-1:0] addend_b = add_sel ? m_f0 : fj[1];
field_adder iadd
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (start | mul_ready_pulse)
    , .a            (addend_a)
    , .b            (addend_b)
    , .ready_pulse  (add_ready_pulse)
    , .ready        (add_ready)
    , .c            (add_out)
    );

// if only we could stay in a mersenne field, where mult
// by 1/2 is just circular shift right by 1 bit!
field_multiplier imul1
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (add_ready_pulse & ~add_sel)
    , .a            (add_out)
    , .b            (`F_HALF)
    , .ready_pulse  (mul_ready_pulse)
    , .ready        (mul_ready[1])
    , .c            (mul_out[1])
    );

// *** Compute c1 ***
wire [`F_NBITS-1:0] sub_out;
field_subtract isub
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (start)
    , .a            (fj[1])
    , .b            (fj[2])
    , .ready_pulse  (sub_ready_pulse)
    , .ready        (sub_ready)
    , .c            (sub_out)
    );

field_multiplier imul0
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (sub_ready_pulse)
    , .a            (sub_out)
    , .b            (`F_HALF)
    , .ready_pulse  ()
    , .ready        (mul_ready[0])
    , .c            (mul_out[0])
    );

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1;
        ready_dly <= 1;
        add_sel <= 0;
        c0_reg <= 0;
    end else begin
        en_dly <= en;
        ready_dly <= ready;
        if (ready_pulse) begin
            add_sel <= 0;
        end else if (add_ready_pulse) begin
            add_sel <= 1;
        end
        if (start) begin
            c0_reg <= fj[0];
        end
    end
end

endmodule
`define __module_prover_compute_c012_fm1
`endif // __module_prover_compute_c012_fm1
