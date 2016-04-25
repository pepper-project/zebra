// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// One layer: prover, verifier intf, and compute layer.
// (C) 2015 Riad S. Wahby

// This hookup is not particularly amenable to pipelining because comp_in
// is shared between computation_layer and prover_layer (these would have
// to be separated, and prover_layer's inputs would probably be retrieved
// from RAM.
//
// However, it demonstrates proper interconnection and lets us generate
// multi-layer circuits for testing.

`ifndef __module_layer_top
`include "simulator.v"
`include "field_arith_defs.v"
`include "gatefn_defs.v"
`include "computation_layer.sv"
`include "prover_layer.sv"
`include "ringbuf_simple.sv"
`include "verifier_interface.sv"
module layer_top
   #( parameter ngates = 8
    , parameter ninputs = 8
    , parameter nmuxsels = 1
    , parameter layer_num = 0

    , parameter [`GATEFN_BITS*ngates-1:0] gates_fn = 0

    , parameter ngbits = $clog2(ngates)         // do not override
    , parameter ninbits = $clog2(ninputs)       // do not override
    , parameter nmuxbits = $clog2(nmuxsels)     // do not override

    , parameter [(ninbits*ngates)-1:0] gates_in0 = 0
    , parameter [(ninbits*ngates)-1:0] gates_in1 = 0
    , parameter [(ngates*nmuxbits)-1:0] gates_mux = 0

    , parameter shuf_plstages = 0
   )( input                 clk
    , input                 rstb

                                                    // computation layer interface
    , input                 en_comp                 // enable computation
    , input  [`F_NBITS-1:0] comp_in [ninputs-1:0]   // input
    , output [`F_NBITS-1:0] comp_out [ngates-1:0]   // output
    , output                comp_ready_pulse        // done with circuit computation
    , output                comp_ready              // "

                                                    // sumcheck interface
    , input                 en_sumchk               // start a sumcheck
    , input          [31:0] id                      // id of present computation

    , input  [nmuxsels-1:0] mux_sel                 // bits for the mux gates

                                                    // compute w0 intf to i+1th layer
    , input                 comp_w0_in              // tell prover: enable w0 computation
    , input  [`F_NBITS-1:0] tau_w0_in               // hand our prover the tau to use
    , output [`F_NBITS-1:0] w0_out [ninbits-1:0]    // output w0 from prover_layer
    , output                w0_ready_out            // prover indicates w0 is ready

                                                    // compute w0 intf to i-1th layer
    , output                comp_w0_out             // tell prover: enable w0 computation
    , output [`F_NBITS-1:0] tau_w0_out              // hand remote prover the tau to use
    , input  [`F_NBITS-1:0] w0_in [ngbits-1:0]      // input w0 from previous layer
    , input                 w0_ready_in             // let us know when it's ready

                                                    // verifier interface interlocks
    , output                w0_done_pulse_out       // tell previous layer we're ready
    , input                 w0_done_pulse_in        // next layer indicates it's ready

    , output                sumchk_ready_pulse      // done with one sumcheck
    , output                sumchk_ready            // "
    );

// check that our parameters are reasonable
generate
    if (ninbits != $clog2(ninputs)) begin: IErr1
        Error_do_not_override_ninbits_in_layer_top __error__();
    end
    if (ngbits != $clog2(ngates)) begin: IErr2
        Error_do_not_override_ngbits_in_layer_top __error__();
    end
    if (nmuxbits != $clog2(nmuxsels)) begin: IErr3
        Error_do_not_override_nmuxbits_in_layer_top __error__();
    end
endgenerate

// one layer of the circuit, computation only
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
    , .en           (en_comp)
    , .v_in         (comp_in)
    , .mux_sel      (mux_sel)
    , .ready_pulse  (comp_ready_pulse)
    , .ready        (comp_ready)
    , .v_out        (comp_out)
    );

// interface to the verifier
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
    , .en                   (en_sumchk)
    , .id                   (id)
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
wire buf_en = f_wren | p_wren;
wire [`F_NBITS-1:0] fp_data;
ringbuf_simple
   #( .nbits        (`F_NBITS)
    , .nwords       (nhpoints)
    ) ibuf
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (buf_en)
    , .wren         (buf_en)
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
    , .v_in             (comp_in)
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
`define __module_layer_top
`endif // __module_layer_top
