// arith.v
// testbench for arith VPI module
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

`include "simulator.v"

module arith;

reg [60:0] c;
reg clk;

initial begin
    c = 61'h1ffffffffffffff0;
    #1 clk = 0;
    #1000 $finish;
end

always @(clk) begin
    clk <= #4 ~clk;
end

always @(posedge clk) begin
    $display("Current value of c = %h", c);
    c = $f_add(5, c);
    c = $f_mul(2, c);
end

endmodule
