// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// shuffle outputs of prover_compute_v (nonsynthesizable; see below)
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// After the Prover computes V(...,tau,...) in a given round of the sumcheck
// protocol, each gate in the circuit needs corresponding values for V(0),
// V(1), and V(2).
//
// Unfortunately, as explained in prover_compute_v, the order of element
// storage in the local registers in prover_compute_v (i.e., at the inputs
// of the multiply-add blocks) does not correspond to the ordering that the
// pergate circuit elements require.
//
// The purpose of this block is to perform the necessary shuffling.
// It works as follows:
//
// When "en" is asserted, a local counter (the shuffle counter) is
// incremented. (When "restart" is asserted at the same time as "en", the
// value of the counter is reset to 0.)
//
// Each input to this circuit is mapped to the outputs in a counter-dependent
// way. In particular, the array v_out[..] comprises a sequence formed by
// repeating each elemtn in the array v_in[..] a number of times equal to
// (2 << counter_value).
//
// In other words, when v_in[] = {1, 2, 3, 4}, then
// 
// if count = 0
//   v_out[] = {1, 1, 2, 2, 3, 3, 4, 4}
//
// if count = 1
//   v_out[] = {1, 1, 1, 1, 2, 2, 2, 2}
//
// if count = 2
//   v_out[] = {1, 1, 1, 1, 1, 1, 1, 1}
//
// ## WARNING regarding synthesizability ##
//
// When synthesizing, you should first get an idea of the clk->q
// delay of the critical path element in the design (most likely the
// field multiplier), and set plstages such that there is sufficient
// pipelining here to accommodate this.

`ifndef __module_prover_shuffle_v
`include "simulator.v"
`include "field_arith_defs.v"
`include "prover_shuffle_v_elem.sv"
module prover_shuffle_v
   #( parameter ngates = 8
    , parameter plstages = 0        // # of _elem stages between pipeline registers
// NOTE do not override parameters below this line //
    , parameter ngates_in = 1 << ($clog2(ngates) - 1)
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 restart

    , input  [`F_NBITS-1:0] v_0_in [ngates_in-1:0]
    , input  [`F_NBITS-1:0] v_1_in [ngates_in-1:0]
    , input  [`F_NBITS-1:0] v_tau_in [ngates_in-1:0]

    , output                ready_pulse
    , output                ready

    , output [`F_NBITS-1:0] v_0 [ngates-1:0]
    , output [`F_NBITS-1:0] v_1 [ngates-1:0]
    , output [`F_NBITS-1:0] v_tau [ngates-1:0]
    );

// make sure parameters have not been overridden
generate
    if (ngates_in != 1 << ($clog2(ngates) - 1)) begin: IErr1
        Error_do_not_override_ngates_in_in_prover_shuffle_v __error__();
    end
endgenerate

// how many layers of shuffle elements do we need?
localparam nlevels = $clog2(ngates) - 1;

// generate enable pulse
reg en_dly;
wire inc = en & ~en_dly;

// counter register - decides which shuffle elements are active
reg [nlevels-1:0] count_reg;
// if restarting, all layers are "inactive"
// at each increment, a new layer becomes active
wire [nlevels-1:0] count_next =
    inc ? (restart ? {(nlevels){1'b0}}
                   : {1'b1,count_reg[nlevels-1:1]})
        : count_reg;

// wires for hooking up the shuffle trees
wire [`F_NBITS-1:0] layer_out_0 [nlevels-1:-1] [ngates_in-1:0];
wire [`F_NBITS-1:0] layer_out_1 [nlevels-1:-1] [ngates_in-1:0];
wire [`F_NBITS-1:0] layer_out_tau [nlevels-1:-1] [ngates_in-1:0];

// generate ready pulse
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

// ready signal that respects the pipeline delay
generate
    if (plstages == 0) begin: RNoPipe
        assign ready = ~inc;
    end else begin: RPipe
        localparam plcount_max = nlevels / plstages;
        localparam bcount = $clog2(plcount_max + 1);    // +1 so we can store plcount

        // counter for pipeline delay
        reg [bcount-1:0] plcount_reg;
        wire plcount_done = plcount_reg == plcount_max;
        wire [bcount-1:0] plcount_next = inc ? 0 : (plcount_done ? plcount_max : plcount_reg + 1);
        assign ready = ~inc & plcount_done;

        // update pl counter
        `ALWAYS_FF @(posedge clk or negedge rstb) begin
            if (~rstb) begin
                plcount_reg <= plcount_max;
            end else begin
                plcount_reg <= plcount_next;
            end
        end
    end
endgenerate

// hookup for inputs and outputs
genvar GateNum;
generate
    // wire up inputs to the first level of the shuffle tree
    assign layer_out_0[-1][0] = v_0_in[0];
    assign layer_out_1[-1][0] = v_1_in[0];
    assign layer_out_tau[-1][0] = v_tau_in[0];

    // try to catch errors by assigning unused elements to X
    for (GateNum = 1; GateNum < ngates_in; GateNum = GateNum + 1) begin: SInputs
        assign layer_out_0[-1][GateNum] = {(`F_NBITS){1'bX}};
        assign layer_out_1[-1][GateNum] = {(`F_NBITS){1'bX}};
        assign layer_out_tau[-1][GateNum] = {(`F_NBITS){1'bX}};
    end

    // wire up outputs
    for (GateNum = 0; GateNum < ngates_in; GateNum = GateNum + 1) begin: SOutputs
        if (GateNum * 2 < ngates) begin: SOutputsEven
            assign v_0[GateNum * 2] = layer_out_0[nlevels-1][GateNum];
            assign v_1[GateNum * 2] = layer_out_1[nlevels-1][GateNum];
            assign v_tau[GateNum * 2] = layer_out_tau[nlevels-1][GateNum];
        end

        if (GateNum * 2 + 1 < ngates) begin: SOutputsOdd
            assign v_0[GateNum * 2 + 1] = layer_out_0[nlevels-1][GateNum];
            assign v_1[GateNum * 2 + 1] = layer_out_1[nlevels-1][GateNum];
            assign v_tau[GateNum * 2 + 1] = layer_out_tau[nlevels-1][GateNum];
        end
    end
endgenerate

// shuffle tree including parameterized pipelining
integer GateNumI;
genvar Layer;
generate
    // generate each layer of the shuffle tree
    for (Layer = 0; Layer < nlevels; Layer = Layer + 1) begin: SLayer // SLAYERRRRRRR
        // hookup wires for pipelining
        localparam this_ngates = 2 << Layer;
        wire [`F_NBITS-1:0] layer_pl_0 [this_ngates-1:0];
        wire [`F_NBITS-1:0] layer_pl_1 [this_ngates-1:0];
        wire [`F_NBITS-1:0] layer_pl_tau [this_ngates-1:0];

        // if we should insert pipelining after this stage, do so
        if ((plstages != 0) && ((Layer + 1) % plstages == 0)) begin: SPipe
            // first, declare registers and their inputs
            reg [`F_NBITS-1:0] layer_reg_0 [this_ngates-1:0];
            reg [`F_NBITS-1:0] layer_reg_1 [this_ngates-1:0];
            reg [`F_NBITS-1:0] layer_reg_tau [this_ngates-1:0];
            `ALWAYS_FF @(posedge clk or negedge rstb) begin
                if (~rstb) begin
                    for (GateNumI = 0; GateNumI < this_ngates; GateNumI = GateNumI + 1) begin
                        layer_reg_0[GateNumI] <= 0;
                        layer_reg_1[GateNumI] <= 0;
                        layer_reg_tau[GateNumI] <= 0;
                    end
                end else begin
                    for (GateNumI = 0; GateNumI < this_ngates; GateNumI = GateNumI + 1) begin
                        layer_reg_0[GateNumI] <= layer_pl_0[GateNumI];
                        layer_reg_1[GateNumI] <= layer_pl_1[GateNumI];
                        layer_reg_tau[GateNumI] <= layer_pl_tau[GateNumI];
                    end
                end
            end

            // then hook up the stage outputs to these registers
            for (GateNum = 0; GateNum < this_ngates; GateNum = GateNum + 1) begin: SPipeHookup
                assign layer_out_0[Layer][GateNum] = layer_reg_0[GateNum];
                assign layer_out_1[Layer][GateNum] = layer_reg_1[GateNum];
                assign layer_out_tau[Layer][GateNum] = layer_reg_tau[GateNum];
            end
        end else begin: SNoPipe
            // otherwise, no registers, just wire straight through
            for (GateNum = 0; GateNum < this_ngates; GateNum = GateNum + 1) begin: SNoPipeHookup
                assign layer_out_0[Layer][GateNum] = layer_pl_0[GateNum];
                assign layer_out_1[Layer][GateNum] = layer_pl_1[GateNum];
                assign layer_out_tau[Layer][GateNum] = layer_pl_tau[GateNum];
            end
        end

        // connect outputs from this layer
        for (GateNum = 0; GateNum < this_ngates / 2; GateNum = GateNum + 1) begin: SGate
            prover_shuffle_v_elem ishuf0
                ( .in_act       (layer_out_0[Layer-1][GateNum])
                , .in_nact_0    (v_0_in[GateNum*2])
                , .in_nact_1    (v_0_in[GateNum*2+1])
                , .act          (count_reg[Layer])
                , .out_0        (layer_pl_0[GateNum*2])
                , .out_1        (layer_pl_0[GateNum*2+1])
                );

            prover_shuffle_v_elem ishuf1
                ( .in_act       (layer_out_1[Layer-1][GateNum])
                , .in_nact_0    (v_1_in[GateNum*2])
                , .in_nact_1    (v_1_in[GateNum*2+1])
                , .act          (count_reg[Layer])
                , .out_0        (layer_pl_1[GateNum*2])
                , .out_1        (layer_pl_1[GateNum*2+1])
                );

            prover_shuffle_v_elem ishuftau
                ( .in_act       (layer_out_tau[Layer-1][GateNum])
                , .in_nact_0    (v_tau_in[GateNum*2])
                , .in_nact_1    (v_tau_in[GateNum*2+1])
                , .act          (count_reg[Layer])
                , .out_0        (layer_pl_tau[GateNum*2])
                , .out_1        (layer_pl_tau[GateNum*2+1])
                );
        end

        // set all other outputs from this layer to X to (maybe) catch errors
        for (GateNum = this_ngates; GateNum < ngates_in; GateNum = GateNum + 1) begin: SDfl
            assign layer_out_0[Layer][GateNum] = {(`F_NBITS){1'bX}};
            assign layer_out_1[Layer][GateNum] = {(`F_NBITS){1'bX}};
            assign layer_out_tau[Layer][GateNum] = {(`F_NBITS){1'bX}};
        end
    end
endgenerate

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_dly <= 1;
        ready_dly <= 1;
        count_reg <= 0;
    end else begin
        en_dly <= en;
        ready_dly <= ready;
        count_reg <= count_next;
    end
end

endmodule
`define __module_prover_shuffle_v
`endif // __module_prover_shuffle_v
