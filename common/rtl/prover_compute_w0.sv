// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// Compute w0 from tau, w2-w1, and w1
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// After the sumcheck is finished, V sends one more value, tau.
// P must evaluate gamma(tau) in order to get w0 for the next round,
// where gamma(t) = (w2 - w1)*t + w1.
//
// The prover layer stores up evaluations of w2-w1 and w1 during
// the protocol, so these inputs are available at the end.

`ifndef __module_prover_compute_w0
`include "simulator.v"
`include "field_arith_defs.v"
`include "prover_compute_w0_elem.sv"
module prover_compute_w0
   #( parameter ninbits = 3
   )( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] w1 [ninbits-1:0]
    , input  [`F_NBITS-1:0] w2_m_w1 [ninbits-1:0]
    , input  [`F_NBITS-1:0] tau

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] w0 [ninbits-1:0]
    );

wire [ninbits-1:0] elem_ready;
assign ready = &elem_ready;
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

genvar GateNum;
generate
    for (GateNum = 0; GateNum < ninbits; GateNum = GateNum + 1) begin: CompW0
        prover_compute_w0_elem iw0elem
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (en)
            , .w1           (w1[GateNum])
            , .w2_m_w1      (w2_m_w1[GateNum])
            , .tau          (tau)
            , .ready_pulse  ()
            , .ready        (elem_ready[GateNum])
            , .w0           (w0[GateNum])
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
`define __module_prover_compute_w0
`endif // __module_prover_compute_w0
