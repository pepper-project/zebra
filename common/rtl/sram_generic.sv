// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// a parameterized SRAM
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// This is a generic sram with 2 ports and configurable size.
// Note that it cheats a little bit in that the address and
// data ports are not registered.

`ifndef __module_sram_generic
`include "simulator.v"
module sram_generic
   #( parameter nbits = 8
    , parameter nwords = 8
// NOTE do note override parameters below this line //
    , parameter naddrb = $clog2(nwords)
   )( input                 clk
    , input                 rstb

    , input                 rden_1
    , input                 wren_1
    , input    [naddrb-1:0] addr_1
    , input     [nbits-1:0] data_1
    , output    [nbits-1:0] q_1

    , input                 rden_2
    , input                 wren_2
    , input    [naddrb-1:0] addr_2
    , input     [nbits-1:0] data_2
    , output    [nbits-1:0] q_2
    );

// make sure parameters have not been overridden
generate
    if (naddrb != $clog2(nwords)) begin: IErr1
        Error_do_not_override_naddrb_in_sram_generic __error__();
    end
endgenerate

integer WordNumC, WordNumF;
reg [nbits-1:0] sram_reg [nwords-1:0], sram_next [nwords-1:0];
reg [nbits-1:0] q_1_out, q_1_next, q_2_out, q_2_next;
assign q_1 = q_1_out;
assign q_2 = q_2_out;

`ALWAYS_COMB begin
    for (WordNumC = 0; WordNumC < nwords; WordNumC = WordNumC + 1) begin
        sram_next[WordNumC] = sram_reg[WordNumC];
    end
    q_1_next = q_1_out;
    q_2_next = q_2_out;

    // can't write and read at the same time. This SRAM is write dominated.
    if (wren_1) begin
        sram_next[addr_1] = data_1;
    end else if (rden_1) begin
        q_1_next = sram_reg[addr_1];
    end

    if (wren_2) begin
        sram_next[addr_2] = data_2;
    end else if (rden_2) begin
        q_2_next = sram_reg[addr_2];
    end
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        for (WordNumF = 0; WordNumF < nwords; WordNumF = WordNumF + 1) begin
            sram_reg[WordNumF] <= 0;
        end
        q_1_out <= 0;
        q_2_out <= 0;
    end else begin
        for (WordNumF = 0; WordNumF < nwords; WordNumF = WordNumF + 1) begin
            sram_reg[WordNumF] <= sram_next[WordNumF];
        end
        q_1_out <= q_1_next;
        q_2_out <= q_2_next;
    end
end

endmodule
`define __module_sram_generic
`endif // __module_sram_generic
