// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// Get w0 for layer0 directly from the Verifier
// (C) Riad S. Wahby <rsw@cs.nyu.edu>

// P cannot compute w0 for the output layer of the ckt; this must come from
// the verifier. This module presents an interface similar to the other
// layers of the circuit for doing this.

`ifndef __module_verifier_interface_w0
`include "simulator.v"
`include "verifier_interface_defs.v"
`include "field_arith_defs.v"
module verifier_interface_w0
   #( parameter ngates = 8
    , parameter ngbits = $clog2(ngates)
   )( input                 clk
    , input                 rstb

    , input                 en
    , input          [31:0] id

    , output                w0_ready
    , output [`F_NBITS-1:0] w0 [ngbits-1:0]
    );

// make sure ngbits is properly computed
generate
    if (ngbits != $clog2(ngates)) begin: IErr1
        Error_do_not_override_ngbits_in_verifier_interface_w0 __error__();
    end
endgenerate

reg [`F_NBITS-1:0] w0_reg [ngbits-1:0];
assign w0 = w0_reg;

reg en_dly;
wire start = en & ~en_dly;
assign w0_ready = ~start;

integer WordF;
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        for (WordF = 0; WordF < ngbits; WordF = WordF + 1) begin
            w0_reg[WordF] <= 0;
        end
        en_dly <= 1;
    end else begin
        if (start) begin
            //$display("Requesting q0 %d %d", id, $time);
            $cmt_request(id, `CMT_Q0, w0_reg, ngbits);
        end
        en_dly <= en;
    end
end

endmodule
`define __module_verifier_interface_w0
`endif // __module_verifier_interface_w0
