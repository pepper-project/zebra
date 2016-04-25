// hw_v_interface_test.v
// test module for hardware verifier's VPI functions

//verifier_poll: check if there is a connection from P, handle it and
//return any values, if applicable. Note: p_out_vec, precomp_out_vec
//should be large enough to hold the response from P.

//call as:
//verifier_action = $verifier_poll(id, result_type, round_out, layer_out, p_out_vec, precomp_out_vec)
//verifier action: 0 if no action required, 1, 2, or 3, if recieved outputs, F_js, or H's respectively.

//note note note: id, result type, etc. are return values, not
//arguments. But they are only written to if verifier_action is
//nonzero. A better way of doing this might be returning p_out_vec,
//precomp_out_vec directly to where they are needed in the simulator.

//if verifier_action is nonzero, then the function arguments are
//written to. (Otherwise they are ignored)

//id is the computation id
//result type is one of the CMT_* constants.
//round_out, layer_out are the round, layer.
//p_out_vec is outputs/coefficients from the prover.
//precomp_out_vec is any corresponding precomputation needed to process p_out_vec.

//$verifier_update(id, result_type, layer, round): indicate that a
//computation was successful, updating the phase. The arguments are
//the same as above, but note here they are used as inputs rather than
//written to as outputs.


`include "simulator.v"
`include "verifier_interface_defs.v"

`define N_MUX_BITS 4
module hw_interface_test;
   int id;
   int round;
   int layer;
   int verifier_action;
   int unsigned result_type;
   reg [60:0] p_out_vec [15:0];
   reg [60:0] precomp_out_vec [15:0];
   reg [`N_MUX_BITS-1:0]  muxBits;
   reg        clk;

initial begin
   muxBits = `N_MUX_BITS'h5;
   #1 clk = 0;
   #1000 $finish;
end

always @(clk) begin
   clk <= #4 ~clk;
end

always @(posedge clk) begin
   verifier_action = $verifier_poll(id, result_type, layer, round, p_out_vec, precomp_out_vec);
   $display("verifier_action:  %d", verifier_action);
   $display("comp_id:          %d", id);
   $display("layer:            %d", layer);
   $display("round:            %d", round);

   if (verifier_action > 0)
     $verifier_update(id, result_type, layer, round);
end

endmodule
