// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// One layer: prover, verifier intf, and compute layer (pipelined version)
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// This version of layer_top is designed for pipelined execution.
//
// Compared to layer_top, the primary difference is the use of computation_layer_pl,
// which instantiates a ring buffer to hold layer inputs for later use by the
// prover.
//
// In addition, this version has some controls that make it easier for the
// cmt_top_pl state machine.

`ifndef __module_layer_top_pl
`include "simulator.v"
`include "field_arith_defs.v"
`include "gatefn_defs.v"
`include "layer_ringbuf_pl.sv"
`include "computation_layer.sv"
`include "prover_layer.sv"
`include "ringbuf_simple.sv"
`include "verifier_interface.sv"
module layer_top_pl
   #( parameter ngates = 8
    , parameter ninputs = 8
    , parameter nmuxsels = 1
    , parameter layer_num = 0

    , parameter [`GATEFN_BITS*ngates-1:0] gates_fn = 0

    , parameter ngbits = $clog2(ngates)     // do not override
    , parameter ninbits = $clog2(ninputs)   // do not override
    , parameter nmuxbits = $clog2(nmuxsels) // do not override

    , parameter [(ninbits*ngates)-1:0] gates_in0 = 0
    , parameter [(ninbits*ngates)-1:0] gates_in1 = 0
    , parameter [(ngates*nmuxbits)-1:0] gates_mux = 0

    , parameter shuf_plstages = 0
   )( input                 clk
    , input                 rstb

    , input                 en              // start computation(s) - MUST BE A PULSE
    , input                 comp_en_in      // *_en_in and *_en_out form a
    , output                comp_en_out     // shift register chain that controls
    , input                 sumchk_en_in    // the currently executing stages
    , output                sumchk_en_out   // of the pipeline

    , input  [nmuxsels-1:0] mux_sel

    , output                active_next     // we'll do *something* next time

    , input  [`F_NBITS-1:0] comp_in [ninputs-1:0]
    , output [`F_NBITS-1:0] comp_out [ngates-1:0]
    , output                comp_ready_pulse
    , output                comp_ready

    , input          [31:0] id_c_in
    , output         [31:0] id_c_out

    , input          [31:0] id_p_in
    , output         [31:0] id_p_out

    , input                 comp_w0_in
    , input  [`F_NBITS-1:0] tau_w0_in
    , output [`F_NBITS-1:0] w0_out [ninbits-1:0]
    , output                w0_ready_out

    , output                comp_w0_out
    , output [`F_NBITS-1:0] tau_w0_out
    , input  [`F_NBITS-1:0] w0_in [ngbits-1:0]
    , input                 w0_ready_in

    , output                w0_done_pulse_out
    , input                 w0_done_pulse_in

    , output                sumchk_ready_pulse
    , output                sumchk_ready
    );

// check that our parameters are reasonable
generate
    if (ninbits != $clog2(ninputs)) begin: IErr1
        Error_do_not_override_ninbits_in_layer_top_pl __error__();
    end
    if (ngbits != $clog2(ngates)) begin: IErr2
        Error_do_not_override_ngbits_in_layer_top_pl __error__();
    end
    if (nmuxbits != $clog2(nmuxsels)) begin: IErr3
        Error_do_not_override_nmuxbits_in_layer_top_pl __error__();
    end
endgenerate

// active_next indicates that either this computation
// or this prover stage are operating.
assign active_next = comp_en_in | sumchk_en_in;

// comp_en_out and sumchk_en_out form a shift register that tracks
// which blocks are currently active
reg comp_en_reg, sumchk_en_reg, en_dly;
assign comp_en_out = comp_en_reg;
assign sumchk_en_out = sumchk_en_reg;
// update comp_en_out and sumchk_en_out when we get an en pulse
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        comp_en_reg <= 0;
        sumchk_en_reg <= 0;
        en_dly <= 0;
    end else begin
        if (en) begin
            comp_en_reg <= comp_en_in;
            sumchk_en_reg <= sumchk_en_in;
        end
        en_dly <= en;
    end
end

// the computation layer itself
computation_layer
   #( .ngates       (ngates)
    , .ninputs      (ninputs)
    , .nmuxsels     (nmuxsels)
    , .gates_fn     (gates_fn)
    , .gates_in0    (gates_in0)
    , .gates_in1    (gates_in1)
    , .gates_mux    (gates_mux)
    ) icomp
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en & comp_en_in)
    , .v_in         (comp_in)
    , .mux_sel      (mux_sel)
    , .ready_pulse  (comp_ready_pulse)
    , .ready        (comp_ready)
    , .v_out        (comp_out)
    );

// layer ringbuf for v_in and id values passed to the prover later
wire [`F_NBITS-1:0] v_in_pl [ninputs-1:0];
layer_ringbuf_pl
   #( .ninputs      (ninputs)
    , .layer_num    (layer_num)
    ) ilbuf
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en)
    , .wren         (comp_en_in)
    , .v_in         (comp_in)
    , .v_in_pl      (v_in_pl)
    , .id_c_in      (id_c_in)
    , .id_c_out     (id_c_out)
    , .id_p_in      (id_p_in)
    , .id_p_out     (id_p_out)
    );

// interface (via VPI) to the verifier
wire [`F_NBITS-1:0] tau;
assign tau_w0_out = tau;
wire p_ready_pulse, p_en, p_restart;
wire [1:0] p_ready_code;
localparam nhpoints = $clog2(ninputs) + 1;
wire [`F_NBITS-1:0] layer_data [nhpoints-1:0];
verifier_interface
   #( .ninputs              (ninputs)
    , .ngates               (ngates)
    , .layer_num            (layer_num)
    ) iintf
    ( .clk                  (clk)
    , .rstb                 (rstb)
    , .en                   (en_dly & sumchk_en_reg)
    , .id                   (id_p_out)
    , .layer_ready_pulse    (p_ready_pulse)
    , .layer_ready_code     (p_ready_code)
    , .layer_data           (layer_data)
    , .en_layer             (p_en)
    , .restart_layer        (p_restart)
    , .tau                  (tau)
    , .comp_w0              (comp_w0_out)
    , .w0_done_pulse        (w0_done_pulse_out)
    , .w0_ready_in          (w0_ready_in)
    , .w0                   (w0_in)
    , .w0_done_in           (w0_done_pulse_in)
    , .ready_pulse          (sumchk_ready_pulse)
    , .ready                (sumchk_ready)
    );

// ringbuf for prover_layer outputs
wire f_wren, p_wren;
wire rbuf_en = f_wren | p_wren;
wire [`F_NBITS-1:0] fp_data;
ringbuf_simple
   #( .nbits        (`F_NBITS)
    , .nwords       (nhpoints)
    ) ipbuf
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (rbuf_en)
    , .wren         (rbuf_en)
    , .d            (fp_data)
    , .q            ()
    , .q_all        (layer_data)
    );

// prover instance
prover_layer
   #( .ngates           (ngates)
    , .ninputs          (ninputs)
    , .nmuxsels         (nmuxsels)
    , .gates_fn         (gates_fn)
    , .gates_in0        (gates_in0)
    , .gates_in1        (gates_in1)
    , .gates_mux        (gates_mux)
    , .shuf_plstages    (shuf_plstages)
    ) iprv
    ( .clk              (clk)
    , .rstb             (rstb)
    , .en               (p_en)
    , .restart          (p_restart)
    , .v_in             (v_in_pl)
    , .tau              (tau)
    , .mux_sel          (mux_sel)
    , .f_wren           (f_wren)
    , .p_wren           (p_wren)
    , .fp_data          (fp_data)
    , .comp_w0          (comp_w0_in)
    , .tau_w0           (tau_w0_in)
    , .w0               (w0_out)
    , .w0_ready_pulse   ()
    , .w0_ready         (w0_ready_out)
    , .ready_pulse      (p_ready_pulse)
    , .ready_code       (p_ready_code)
    );

endmodule
`define __module_layer_top_pl
`endif // __module_layer_top_pl
