// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// Compute one layer of an arithmetic circuit.
// (C) Riad S. Wahby <rsw@cs.nyu.edu>

// Given the same parameters as a prover_layer, this circuit just produces
// the output of that layer in the arithmetic circuit.

`ifndef __module_computation_layer
`include "simulator.v"
`include "field_arith_defs.v"
`include "gatefn_defs.v"
`include "computation_gatefn.sv"
module computation_layer
   #( parameter ngates = 8
    , parameter ninputs = 8
    , parameter nmuxsels = 1                // number of entries in mux_sel

    , parameter [`GATEFN_BITS*ngates-1:0] gates_fn = 0

    , parameter ninbits = $clog2(ninputs)   // do not override
    , parameter nmuxbits = $clog2(nmuxsels) // do not override

    , parameter [(ninbits*ngates)-1:0] gates_in0 = 0
    , parameter [(ninbits*ngates)-1:0] gates_in1 = 0
    , parameter [(ngates*nmuxbits)-1:0] gates_mux = 0   // which gate goes to which mux_sel input?
   )( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] v_in [ninputs-1:0]

    , input  [nmuxsels-1:0] mux_sel

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] v_out [ngates-1:0]
    );

// make sure params are ok
generate
    if (ninbits != $clog2(ninputs)) begin: IErr1
        Error_do_not_override_ninbits_in_computation_layer __error__();
    end
    if (nmuxbits != $clog2(nmuxsels)) begin: IErr2
        Error_do_not_override_nmuxbits_in_computation_layer __error__();
    end
endgenerate

wire [ngates-1:0] gate_ready;
assign ready = &gate_ready;
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

genvar GateNum;
generate
    for (GateNum = 0; GateNum < ngates; GateNum = GateNum + 1) begin: CompInst
        localparam [`GATEFN_BITS-1:0] gfn = gates_fn[(GateNum*`GATEFN_BITS) +: `GATEFN_BITS];
        localparam [ninbits-1:0] gi0 = gates_in0[(GateNum*ninbits) +: ninbits];
        localparam [ninbits-1:0] gi1 = gates_in1[(GateNum*ninbits) +: ninbits];

        // make sure that gmux is at least 1 bit wide
        localparam nb = nmuxbits == 0 ? 1 : nmuxbits;
        localparam [nmuxbits-1:0] gmux = gates_mux[(GateNum*nmuxbits) +: nb];

        if (gi0 >= ninputs || gi1 >= ninputs) begin: IErr3
            Illegal_input_number_declared_for_gate __error__();
        end

        // abstract gate function
        computation_gatefn
           #( .gate_fn      (gfn)
            ) igatefn
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (en)
            , .mux_sel      (mux_sel[gmux])
            , .in0          (v_in[gi0])
            , .in1          (v_in[gi1])
            , .ready_pulse  ()
            , .ready        (gate_ready[GateNum])
            , .out          (v_out[GateNum])
            );
    end
endgenerate

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        ready_dly <= 1;
    end else begin
        ready_dly <= ready;
    end
end

endmodule
`define __module_computation_layer
`endif // __module_computation_layer
