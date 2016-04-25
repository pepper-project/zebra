// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// testbench for prover_compute_c012_fm1.sv
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

`include "prover_compute_c012_fm1.sv"
module prover_compute_c012_fm1_test ();

integer rseed, curtime;
reg [`F_NBITS-1:0] fj [2:0];
reg clk, rstb, en, trig;

wire ready_pulse;
wire ready;

wire [`F_NBITS-1:0] c [2:0];

prover_compute_c012_fm1 icomp
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en | trig)
    , .fj           (fj)
    , .ready_pulse  (ready_pulse)
    , .ready        (ready)
    , .c            (c)
    );

initial begin
    rseed = 1;
    curtime = 0;
`ifdef SIMULATOR_IS_ICARUS
    $dumpfile("prover_compute_c012_fm1_test.fst");
    $dumpvars;
    $dumpvars(0, fj[0], fj[1], fj[2], c[0], c[1], c[2]);
    $dumpvars(0, icomp.mul_out[0], icomp.mul_out[1]);
`else
    $shm_open("prover_compute_c012_fm1_test.shm");
    $shm_probe("ASCM");
`endif
    randomize_inputs();
    clk = 0;
    rstb = 0;
    trig = 0;
    en = 0;
    #1 rstb = 1;
    clk = 1;
    #3 trig = 1;
    #2 trig = 0;
    #1000 $finish;
end

`ALWAYS_FF @(posedge clk) begin
    if (ready_pulse) begin
        randomize_inputs();
        en <= 1;
    end else begin
        en <= 0;
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task randomize_inputs;
    integer i;
begin
    if (curtime != 0) begin
        $display("** Round complete, %d cycles elapsed", ($time - curtime)/2);
    end
    curtime = $time;
    for (i = 0; i < 3; i = i + 1) begin
        fj[i] = $random(rseed);
        fj[i] = {fj[i][31:0],32'b0} | $random(rseed);
    end
end
endtask

endmodule
