// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// compute the values of V_{i+1}(gamma(.))
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// After the end of the sumcheck, the Prover returns to the Verifier a set of
// evaluations of V_{i+1} at points given by a function gamma: F -> F^b
// (b = lg(G), G = number of gates at level i + 1)
//
//   gamma(t) = (w2 - w1)*t + w1
//
// where w2, w1 \in F^b are vectors of random points supplied by the Verifier
// during the sumcheck protocol.
//
// Recall that V_{i+1}(u), u \in F^b can be written as
//
//   G       b - 1
//  ___      _____
//  \    V    | |  X    (u   )
//  /__   g   | |   g[k]  k+1
// g = 1     k = 0
//
// where V_g is the output of the gth gate in the i+1th level,
// g[i] represents the ith bit of the binary expansion of g, and
// u_{i} is the ith element of the vector u.
//
// In total, P must compute V_{i+1} at b+1 points gamma(i), i \in {0, 1, ..., b}.
// In the second half of the sumcheck protocol (i.e., after all elements
// of w1 are available, and as each element of w2 comes from the Verifier),
// P can begin computing these V_g. Each of the b+1 evaluations requires
// G multiplications in each round, one multiplication for each element
// of the outer summation above.
//
// Because each sumcheck round takes O(lgG) time (due to the adder tree),
// we can accomplish this computation with G adders, each computing b+1
// products.

`ifndef __module_prover_compute_h
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_adder.sv"
`include "field_one_minus.sv"
`include "prover_compute_h_elem.sv"
`include "ringbuf_simple.sv"
module prover_compute_h
   #( parameter ngates = 8
// NOTE do not override parameters below this line //
    , parameter npoints = $clog2(ngates)+1
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 restart

    , input  [`F_NBITS-1:0] v_in [ngates-1:0]
    , input  [`F_NBITS-1:0] m_w1  // precomputed negation of w1
    , input  [`F_NBITS-1:0] w2

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] w2_m_w1 // w2 - w1 - save for later

    , input                 p_rden
    , output [`F_NBITS-1:0] p_out [ngates-1:0]
    );

// make sure that params have not been overridden
generate
    if (npoints != $clog2(ngates) + 1) begin: IErr1
        Error_do_not_override_npoints_in_prover_compute_h __error__();
    end
    if (npoints < 3) begin: IErr2
        Illegal_parameter__ngates_must_be_at_least_3 __error__();
    end
endgenerate

wire [`F_NBITS-1:0] v_data [ngates-1:0];
wire [`F_NBITS-1:0] v_q [ngates-1:0];

// count_reg keeps track of which of the b+1 evals we're currently doing
localparam cnbits = $clog2(npoints + 1);
reg [cnbits-1:0] count_reg, count_next;
wire count_is_zero = count_reg == 0;
wire count_is_one = count_reg == 1;
wire count_is_last = count_reg == npoints - 1;
wire count_is_done = count_reg >= npoints;
wire do_mult = ~(count_is_zero | count_is_one | count_is_done);

// compute w2 - w1, assuming we've been given the negation of w1
// (which should have been computed and stored on the round that
// V gave P w1)
wire add_ready, add_ready_pulse, onem_ready;
wire [`F_NBITS-1:0] add_out, add_onem;
reg [`F_NBITS-1:0] w2_m_w1_reg, w2_m_w1_next;
assign w2_m_w1 = w2_m_w1_reg;

// multiplier-related wires
wire [ngates+1:0] mult_ready;
assign mult_ready[ngates+1:ngates] = {add_ready, onem_ready};
wire allmult_rdy = &(mult_ready);
reg allmult_rdy_dly;
wire allmult_rdy_pulse = allmult_rdy & ~allmult_rdy_dly;

// general control bits
reg en_dly, en_reg, en_next, restart_reg, restart_next;
wire start = en & ~en_dly & count_is_done;

// ready signals
reg ready_dly;
assign ready = count_is_done & ~start;
assign ready_pulse = ready & ~ready_dly;

// when count_reg == 0, compute w2-w1; otherwise, compute the next gamma
wire [`F_NBITS-1:0] addend_a = (count_is_zero | count_is_one) ? w2 : add_out;
wire [`F_NBITS-1:0] addend_b = count_is_zero ? m_w1 : w2_m_w1_reg;
// compute next value of gamma
field_adder iadd
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en_reg & ~count_is_last)
    , .a            (addend_a)
    , .b            (addend_b)
    , .ready_pulse  (add_ready_pulse)
    , .ready        (add_ready)
    , .c            (add_out)
    );

// after we've computed next value of gamma, compute 1-gamma
// This only runs after the adder when the following cycle is
// one in which the multipliers will be running (else we don't
// need the 1-gamma value).
field_one_minus ionem
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (add_ready_pulse & ~count_is_zero)
    , .a            (add_out)
    , .ready_pulse  ()
    , .ready        (onem_ready)
    , .c            (add_onem)
    );

// instantiate ring buffers to hold the point data
wire buf_en = (allmult_rdy_pulse & do_mult) | p_rden;
genvar GateNum;
generate
    for (GateNum = 0; GateNum < ngates; GateNum = GateNum + 1) begin: BufInst
        ringbuf_simple
           #( .nbits        (`F_NBITS)
            , .nwords       (npoints-2)
            ) ibuf
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (buf_en)
            , .wren         (do_mult)
            , .d            (v_data[GateNum])
            , .q            (v_q[GateNum])
            , .q_all        ()
            );
        assign p_out[GateNum] = v_q[GateNum];
    end
endgenerate

// instantiate the multipliers to update the points
localparam nidbits = $clog2(ngates);
generate
    for (GateNum = 0; GateNum < ngates; GateNum = GateNum + 1) begin: MultInst
        localparam [nidbits-1:0] gate_id = GateNum;
        prover_compute_h_elem
           #( .nidbits      (nidbits)
            , .gate_id      (gate_id)
            ) ielem
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (en_reg & do_mult)
            , .restart      (restart_reg)
            , .done         (count_is_last)
            , .v_in         (v_in[GateNum])
            , .v_q          (v_q[GateNum])
            , .tau          (add_out)
            , .m_tau_p1     (add_onem)
            , .ready_pulse  ()
            , .ready        (mult_ready[GateNum])
            , .v_data       (v_data[GateNum])
            );
    end
endgenerate

`ALWAYS_COMB begin
    count_next = count_reg;
    w2_m_w1_next = w2_m_w1_reg;
    restart_next = restart_reg;
    // write ripples to read ripples to enable
    en_next = allmult_rdy_pulse & ~count_is_last;

    if (start) begin
        count_next = 0;
        restart_next = restart;
        en_next = 1;
    end else if (~count_is_done) begin
        if (allmult_rdy_pulse) begin
            // finished the current multiplication
            count_next = count_next + 1;
            if (count_is_zero) begin
                // save w2-w1
                w2_m_w1_next = add_out;
            end
        end
    end
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        allmult_rdy_dly <= 1;
        ready_dly <= 1;
        en_dly <= 1;
        count_reg <= npoints;
        w2_m_w1_reg <= 0;
        restart_reg <= 0;
        en_reg <= 0;
    end else begin
        allmult_rdy_dly <= allmult_rdy;
        ready_dly <= ready;
        en_dly <= en;
        count_reg <= count_next;
        w2_m_w1_reg <= w2_m_w1_next;
        restart_reg <= restart_next;
        en_reg <= en_next;
    end
end

endmodule
`define __module_prover_compute_h
`endif // __module_prover_compute_h
