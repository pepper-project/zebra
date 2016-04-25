// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// compute gate's total contribution to sumcheck outputs
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// Given a gate's add~ or mul~ contribution and the result of evaluating its
// gatefn (i.e., V(.)+V(.) or V(.)*V(.)), compute the contribution to this
// round of the sumcheck for F_j(0), F_j(1), and F_j(2)

`ifndef __module_pergate_compute_fj
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_multiplier.sv"
module pergate_compute_fj
    ( input                 clk
    , input                 rstb

    , input                 en
    , input  [`F_NBITS-1:0] gatefn [2:0]
    , input  [`F_NBITS-1:0] addmul [2:0]

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] out [2:0]
    );

// ready wires
wire [2:0] mul_ready;
assign ready = &(mul_ready);
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

genvar InstID;
generate
    for (InstID = 0; InstID < 3; InstID = InstID + 1) begin: IMul
        field_multiplier imul
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (en)
            , .a            (gatefn[InstID])
            , .b            (addmul[InstID])
            , .ready_pulse  ()
            , .ready        (mul_ready[InstID])
            , .c            (out[InstID])
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
`define __module_pergate_compute_fj
`endif // __module_pergate_compute_fj
