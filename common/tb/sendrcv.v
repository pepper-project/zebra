// sendrcv.v
// test module for VPI network communication

`include "simulator.v"
`include "verifier_interface_defs.v"

`define N_MUX_BITS 4
module sendrcv;

   reg [31:0] id;
   reg [60:0] inputs [15:0];
   reg [60:0] outputs [7:0];
   reg [60:0] q0 [2:0];
   reg [60:0] f012 [2:0];
   reg [60:0] r;
   reg [60:0] h [4:0];
   reg [60:0] q1 [4:0];
   reg [`N_MUX_BITS-1:0]  muxBits;
   
   reg        clk;

initial begin
   
   outputs[0] = 61'h1;
   outputs[1] = 61'h2;
   outputs[2] = 61'h3;
   outputs[3] = 61'h4;
   outputs[4] = 61'h5;
   outputs[5] = 61'h6;
   outputs[6] = 61'h7;
   outputs[7] = 61'h8;
   
   #1 clk = 0;
   #1000 $finish;
end

always @(clk) begin
   clk <= #4 ~clk;
end

always @(posedge clk) begin
   id = $cmt_init(32,3); //cmt_init takes width, depth of cmt circuit as parameters.
   $display("\n\n\nusing computation id %d\n", id);
   $cmt_request(0, `CMT_MUXSEL, muxBits, `N_MUX_BITS);
   $display("muxbits: %h", muxBits);
   
   $cmt_request(id, `CMT_INPUT, inputs, 16);

   outputs[1] = $f_add(inputs[1], outputs[1]);
   
   $cmt_send(id, `CMT_OUTPUT, outputs, 8);

   $cmt_request(id, `CMT_Q0, q0, 3);

   f012[0] = 61'h5;
   f012[1] = 61'h7;
   f012[2] = 61'h9;
   
   $cmt_send(id, `CMT_F012, f012, 0, 0);
   $cmt_request(id, `CMT_R, r, 0, 0);

   $cmt_send(id, `CMT_F012, f012, 0, 1);
   $cmt_request(id, `CMT_R, r, 0, 1);

   $cmt_send(id, `CMT_F012, f012, 0, 2);
   $cmt_request(id, `CMT_R, r, 0, 2);

   $cmt_send(id, `CMT_F012, f012, 0, 3);
   $cmt_request(id, `CMT_R, r, 0, 3);

   $cmt_send(id, `CMT_F012, f012, 0, 4);
   $cmt_request(id, `CMT_R, r, 0, 4);

   $cmt_send(id, `CMT_F012, f012, 0, 5);
   $cmt_request(id, `CMT_R, r, 0, 5);

   $cmt_send(id, `CMT_F012, f012, 0, 6);
   $cmt_request(id, `CMT_R, r, 0, 6);

   $cmt_send(id, `CMT_F012, f012, 0, 7);
   $cmt_request(id, `CMT_R, r, 0, 7);


   h[0] = 61'h364;
   h[1] = 61'h324;
   h[2] = 61'h12;
   h[3] = 61'h1;
   h[4] = 61'h5;

   $cmt_send(id, `CMT_H, h, 0, 5);
   $cmt_request(id, `CMT_QI, q1, 1, 4);

   $cmt_send(id, `CMT_F012, f012, 1, 0);
   $cmt_request(id, `CMT_R, r, 1, 0);

   $cmt_send(id, `CMT_F012, f012, 1, 1);
   $cmt_request(id, `CMT_R, r, 1, 1);

   $cmt_send(id, `CMT_F012, f012, 1, 2);
   $cmt_request(id, `CMT_R, r, 1, 2);

   $cmt_send(id, `CMT_F012, f012, 1, 3);
   $cmt_request(id, `CMT_R, r, 1, 3);

   $cmt_send(id, `CMT_F012, f012, 1, 4);
   $cmt_request(id, `CMT_R, r, 1, 4);

   $cmt_send(id, `CMT_F012, f012, 1, 5);
   $cmt_request(id, `CMT_R, r, 1, 5);

   $cmt_send(id, `CMT_F012, f012, 1, 6);
   $cmt_request(id, `CMT_R, r, 1, 6);

   $cmt_send(id, `CMT_F012, f012, 1, 7);
   $cmt_request(id, `CMT_R, r, 1, 7);

   $cmt_send(id, `CMT_H, h, 0, 5);
   
   
end

endmodule
