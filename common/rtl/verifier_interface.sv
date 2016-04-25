// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// Interface to VPI verifier code
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// This module acts as an interface between the prover and the verifier.
// After each round it takes the prover's outputs and sends them to the
// verifier, and then drives the prover with the replies.

`ifndef __module_verifier_interface
`include "simulator.v"
`include "verifier_interface_defs.v"
`include "field_arith_defs.v"
`include "shiftreg_simple.sv"
module verifier_interface
   #( parameter ninputs = 8
    , parameter ngates = 8
    , parameter layer_num = 0
    , parameter nhpoints = $clog2(ninputs) + 1      // do not override!
    , parameter ngbits = $clog2(ngates)             // "
   )( input                 clk
    , input                 rstb

    , input                 en
    , input          [31:0] id

                                                // interface to this layer of the prover
    , input                 layer_ready_pulse   // ready pulse from the layer
    , input           [1:0] layer_ready_code    // code
    , input  [`F_NBITS-1:0] layer_data [nhpoints-1:0]   // data from ringbuf connected to layer
    , output                en_layer            // enable this layer
    , output                restart_layer       // start over
    , output [`F_NBITS-1:0] tau                 // random field element from this layer

                                                // interface to previous layer's w0 computation
    , output                comp_w0             // tell previous layer to compute w0
    , output                w0_done_pulse       // tell previous layer intf that we've got w0
    , input                 w0_ready_in         // w0 is ready, says previous layer
    , input  [`F_NBITS-1:0] w0 [ngbits-1:0]     // ...and here are the results
    , input                 w0_done_in          // next layer intf saying it's g2g

    , output                ready_pulse
    , output                ready
    );

// make sure nhpoints, ngbits are correct for this instantiation
generate
    if (nhpoints != $clog2(ninputs) + 1) begin: IErr1
        Error_do_not_override_nhpoints_in_verifier_interface __error__();
    end
    if (ngbits != $clog2(ngates)) begin: IErr2
        Error_do_not_override_ngbits_in_verifier_interface __error__();
    end
endgenerate

// wires for f_j
wire [`F_NBITS-1:0] fj_vals [2:0];
assign fj_vals[2] = layer_data[nhpoints-1];
assign fj_vals[1] = layer_data[nhpoints-2];
assign fj_vals[0] = layer_data[nhpoints-3];

// shift register: hold values of w0
wire [`F_NBITS-1:0] sreg_out;
reg wren_sreg, wren_sreg_next;
assign w0_done_pulse = wren_sreg;   // when we update sreg, prev layer can continue
reg shen_sreg, shen_sreg_next;
shiftreg_simple
   #( .nbits        (`F_NBITS)
    , .nwords       (ngbits)
    ) isreg
    ( .clk          (clk)
    , .rstb         (rstb)
    , .wren         (wren_sreg)
    , .shen         (shen_sreg)
    , .d            (w0)
    , .q            (sreg_out)
    , .q_all        ()
    );

// next layer has gotten w0 from this layer
reg next_layer_ready;

// select either w0 or incoming tau from V
reg w0_sel_reg, w0_sel_next;
reg [`F_NBITS-1:0] tau_reg;
assign tau = w0_sel_reg ? sreg_out : tau_reg;

// control this layer
reg en_layer_reg, en_layer_next;
assign en_layer = en_layer_reg;
reg restart_reg, restart_next;
assign restart_layer = restart_reg;

// round counter
localparam nrounds = 2 * $clog2(ninputs);
localparam nrbits = $clog2(nrounds);
reg [nrbits-1:0] round_reg, round_next;

// state machine
enum { ST_IDLE, ST_GETW0, ST_START, ST_RUN } state_reg, state_next;

// enable for comp_w0 is based on begin in ST_GETW0
// This is possible because comp_w0 is edge triggered.
assign comp_w0 = state_reg == ST_GETW0;
// ready, ready pulse
assign ready = state_reg == ST_IDLE & ~en;
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;
wire inST_RUN = state_reg == ST_RUN;

`ALWAYS_COMB begin
    wren_sreg_next = 0;
    shen_sreg_next = 0;
    w0_sel_next = w0_sel_reg;
    en_layer_next = 0;
    restart_next = restart_reg;
    state_next = state_reg;
    round_next = round_reg;

    case (state_reg)
        ST_IDLE: begin
            if (en) begin
                w0_sel_next = 0;
                round_next = 0;
                state_next = ST_GETW0;
            end
        end

        ST_GETW0: begin
            // wait until w0 is computed
            if (w0_ready_in) begin
                wren_sreg_next = 1;
                state_next = ST_START;
            end
        end

        ST_START: begin
            // do not start until the next layer has gotten its w0 values!
            if (next_layer_ready) begin
                w0_sel_next = 1;
                restart_next = 1;
                en_layer_next = 1;
                state_next = ST_RUN;
            end
        end

        ST_RUN: begin
            if (shen_sreg) begin
                // we're continuing the precomputation
                en_layer_next = 1;
            end else if (layer_ready_pulse) begin
                case (layer_ready_code)
                    2'b00: begin
                        // precomputation continues
                        // but don't start until the shift register is done shifting!
                        restart_next = 0;
                        shen_sreg_next = 1;
                    end

                    2'b01: begin
                        // fj are waiting to be sent
                        w0_sel_next = 0;
                        round_next = round_reg + 1;
                        en_layer_next = 1;
                    end

                    2'b10: begin
                        //$display("sending h %d %d %d %d", id, layer_num, nhpoints, $time);
                        $cmt_send(id, `CMT_H, layer_data, layer_num, nhpoints);
                        state_next = ST_IDLE;
                    end

                    2'b11: begin
                        $display("**** ERROR: got 11 ready code (%d:%d)!", layer_num, round_reg);
                        $finish;
                    end
                endcase
            end
        end
    endcase
end

// separate ALWAYS_FF for updating tau_reg
// This is because ncverilog gets confused otherwise.
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        tau_reg <= 0;
    end else begin
        case (state_reg)
            ST_IDLE: begin
                if (en) begin
                    if (layer_num != 0) begin
                        //$display("Requesting tau %d %d %d", id, layer_num, $time);
                        $cmt_request(id, `CMT_TAU, tau_reg, layer_num);
                    end
                end
            end

            ST_RUN: begin
                if (layer_ready_pulse && layer_ready_code == 2'b01) begin
                    //$display("sending f012 %d %d %d %d", id, layer_num, round_reg, $time);
                    $cmt_send(id, `CMT_F012, fj_vals, layer_num, round_reg);
                    //$display("requesting r %d %d %d %d", id, layer_num, round_reg, $time);
                    $cmt_request(id, `CMT_R, tau_reg, layer_num, round_reg);
                end
            end
        endcase
    end
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        next_layer_ready <= 1;
        ready_dly <= 1;
        wren_sreg <= 0;
        shen_sreg <= 0;
        w0_sel_reg <= 0;
        en_layer_reg <= 0;
        restart_reg <= 0;
        state_reg <= ST_IDLE;
        round_reg <= 0;
    end else begin
        if (w0_done_in) begin
            next_layer_ready <= 1;
        end else if (inST_RUN) begin
            next_layer_ready <= 0;
        end
        ready_dly <= ready;
        wren_sreg <= wren_sreg_next;
        shen_sreg <= shen_sreg_next;
        w0_sel_reg <= w0_sel_next;
        en_layer_reg <= en_layer_next;
        restart_reg <= restart_next;
        state_reg <= state_next;
        round_reg <= round_next;
    end
end

endmodule
`define __module_verifier_interface
`endif // __module_verifier_interface
