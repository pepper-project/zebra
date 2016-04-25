// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// compute a given gate's function (add or mul)
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// Each gate is either an add or a multiply.
//
// This module is a common interface; add or mul is selected by a parameter.
//
// For the sake of simplicity elsewhere, we use a separate gate for each
// evaluation (V(0), V(1), and V(2)). For space savings, this could be done
// sequentially instead, with an obvious speed penalty.

`ifndef __module_pergate_compute_gatefn_seq
`include "simulator.v"
`include "field_arith_defs.v"
`include "gatefn_defs.v"
`include "computation_gatefn.sv"
module pergate_compute_gatefn_seq
   #( parameter [`GATEFN_BITS-1:0] gate_fn = 0
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 mux_sel
    , input  [`F_NBITS-1:0] in0 [2:0]
    , input  [`F_NBITS-1:0] in1 [2:0]

    , output                ready
    , output [`F_NBITS-1:0] gatefn [2:0]
    );

// control bits for shared gatefn
reg [`F_NBITS-1:0] fn_a, fn_b;
reg en_fn, en_fn_next;
wire [`F_NBITS-1:0] fn_c;
wire fn_ready;
computation_gatefn
   #( .gate_fn      (gate_fn)
    ) igatefn
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en_fn)
    , .mux_sel      (mux_sel)
    , .in0          (fn_a)
    , .in1          (fn_b)
    , .ready_pulse  ()
    , .ready        (fn_ready)
    , .out          (fn_c)
    );

// state machine
enum { ST_IDLE, ST_FN0, ST_FN1, ST_FN2 } state_reg, state_next;
wire inST_IDLE = state_reg == ST_IDLE;

assign ready = inST_IDLE & ~en;

reg [`F_NBITS-1:0] fn_reg [1:0];
reg [`F_NBITS-1:0] fn_next [1:0];
assign gatefn[0] = fn_reg[0];
assign gatefn[1] = fn_reg[1];
assign gatefn[2] = fn_c;

`ALWAYS_COMB begin
    en_fn_next = 0;
    fn_next[0] = fn_reg[0];
    fn_next[1] = fn_reg[1];
    state_next = state_reg;
    fn_a = {(`F_NBITS){1'bX}};
    fn_b = {(`F_NBITS){1'bX}};

    case (state_reg)
        ST_IDLE: begin
            if (en) begin
                en_fn_next = 1;
                state_next = ST_FN0;
            end
        end

        ST_FN0: begin
            fn_a = in0[0];
            fn_b = in1[0];
            if (fn_ready) begin
                en_fn_next = 1;
                fn_next[0] = fn_c;
                state_next = ST_FN1;
            end
        end

        ST_FN1: begin
            fn_a = in0[1];
            fn_b = in1[1];
            if (fn_ready) begin
                en_fn_next = 1;
                fn_next[1] = fn_c;
                state_next = ST_FN2;
            end
        end

        ST_FN2: begin
            fn_a = in0[2];
            fn_b = in1[2];
            if (fn_ready) begin
                state_next = ST_IDLE;
            end
        end

        default: begin
            state_next = ST_IDLE;
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_fn <= 0;
        fn_reg[0] <= 0;
        fn_reg[1] <= 0;
        state_reg <= ST_IDLE;
    end else begin
        en_fn <= en_fn_next;
        fn_reg[0] <= fn_next[0];
        fn_reg[1] <= fn_next[1];
        state_reg <= state_next;
    end
end

endmodule
`define __module_pergate_compute_gatefn_seq
`endif // __module_pergate_compute_gatefn_seq
