// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// testbench for field adder and multiplier modules
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

`include "simulator.v"

`include "field_adder.sv"
`include "field_multiplier.sv"
`include "field_subtract.sv"
module field_arith_test
   ();

localparam nbits = `F_NBITS;

reg [nbits-1:0] c1;
reg [nbits-1:0] c1_next;
reg [nbits-1:0] c2;
reg [nbits-1:0] c2_next;
reg [nbits-1:0] c3;
reg [nbits-1:0] c3_next;

reg clk;
reg rstb;
reg trig;
reg add_en;
reg mul_en;
reg sub_en;

wire [nbits-1:0] foo = ~c1;

wire add_rdy, mul_rdy, add_c, mul_c, sub_rdy;
wire [nbits-1:0] add_out, mul_out, sub_out;
integer rseed;

field_subtract isub
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (sub_en)
    , .a            (c2)
    , .b            (c1)
    , .ready_pulse  (sub_rdy)
    , .ready        ()
    , .c            (sub_out)
    );

field_multiplier imul
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (mul_en)
    , .a            (c2)
    , .b            (c3)
    , .ready_pulse  (mul_rdy)
    , .ready        ()
    , .c            (mul_out)
    );

field_adder iadd
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (add_en)
    , .a            (c1)
    , .b            (c3)
    , .ready_pulse  (add_rdy)
    , .ready        ()
    , .c            (add_out)
    );

initial begin
    rseed = 0;
    $dumpfile("field_arith_test.vcd");
    $dumpvars;
    rstb = 1;
    trig = 0;
    #1 rstb = 0;
    #2 rstb = 1;
    clk = 0;
    trig = 1;
    #4 trig = 0;
    #2000 $finish;
end

`ALWAYS_COMB begin
    c1_next = c1;
    c2_next = c2;
    c3_next = c3;

    if (add_rdy) begin
        c1_next = add_out;
    end

    if (mul_rdy) begin
        c2_next = mul_out;
    end

    if (sub_rdy) begin
        c3_next = sub_out;
    end
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        c1 <= $unsigned($random(rseed)) * $unsigned($random(rseed));
        c2 <= $unsigned($random(rseed)) * $unsigned($random(rseed));
        c3 <= $unsigned($random(rseed)) * $unsigned($random(rseed));
        add_en <= 0;
        mul_en <= 0;
        sub_en <= 0;
    end else begin
        c1 <= c1_next;
        c2 <= c2_next;
        sub_en <= add_rdy;
        add_en <= mul_rdy | trig;
        mul_en <= sub_rdy;
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #2 ~clk;
end

endmodule
