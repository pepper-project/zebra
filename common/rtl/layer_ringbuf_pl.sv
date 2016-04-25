// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// set of ringbuffers to store inputs for one computation/verifier pair
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// The computation/proving pipeline can be thought of as being "folded";
// that is, each computation layer has a corresponding prover layer, and
// these layers are instantiated together; and the pipeline sequence first
// goes through computation layers i-1 to 0, and then through prover layers
// 0 to i-1.
//
// When producing a proof for a computation instance, the jth prover layer
// needs the inputs that were presented to the jth computation layer when
// it worked on that instance. This module holds those values.
//
// The overall pipeline looks like this:
//
//   INPUTS                           PROOFS
//      |                               ^
//      V                               |
// +---------+    +-----------+    +---------+
// |         |    |           |    |         |
// | C_(i-1) | -> | buf_(i-1) | -> | P_(i-1) |
// |         |    |           |    |         |
// +---------+    +-----------+    +---------+
//      |                               ^
//      V                               |
//
//     ...                             ...
//
//      |                               ^
//      V                               |
// +---------+    +-----------+    +---------+
// |         |    |           |    |         |
// |   C_1   | -> |   buf_1   | -> |   P_1   |
// |         |    |           |    |         |
// +---------+    +-----------+    +---------+
//      |                               ^
//      V                               |
// +---------+    +-----------+    +---------+
// |         |    |           |    |         |
// |   C_0   | -> |   buf_0   | -> |   P_0   |
// |         |    |           |    |         |
// +---------+    +-----------+    +---------+
//      |
//      V
//   OUTPUTS
//
// Unfortunately, this style is not cheap: across all bufs, the total vector
// storage is equal to (d^2+d) for a depth d circuit; and each vector contains
// a number of values equal to the width of the corresponding layer!

`ifndef __module_layer_ringbuf_pl
`include "simulator.v"
`include "field_arith_defs.v"
`include "ringbuf_simple.sv"
module layer_ringbuf_pl
   #( parameter ninputs = 8
    , parameter layer_num = 0
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 wren

    , input  [`F_NBITS-1:0] v_in [ninputs-1:0]
    , output [`F_NBITS-1:0] v_in_pl [ninputs-1:0]

    , input          [31:0] id_c_in
    , output         [31:0] id_c_out

    , input          [31:0] id_p_in
    , output         [31:0] id_p_out
    );

// generate ringbufs to hold previous evaluations
localparam bdepth = 2 * (layer_num + 1);
genvar BufNum;
generate
    for (BufNum = 0; BufNum < ninputs; BufNum = BufNum + 1) begin: IRBuf
        // one buffer for each word of the output
        ringbuf_simple
           #( .nbits        (`F_NBITS)
            , .nwords       (bdepth)
            ) ibuf
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (en)
            , .wren         (wren)
            , .d            (v_in[BufNum])
            , .q            (v_in_pl[BufNum])
            , .q_all        ()
            );
    end
endgenerate

reg [31:0] id_c_reg;
assign id_c_out = id_c_reg;
reg [31:0] id_p_reg;
assign id_p_out = id_p_reg;
`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        id_c_reg <= 0;
        id_p_reg <= 0;
    end else begin
        id_c_reg <= en ? id_c_in : id_c_reg;
        id_p_reg <= en ? id_p_in : id_p_reg;
    end
end

endmodule
`define __module_layer_ringbuf_pl
`endif // __module_layer_ringbuf_pl
