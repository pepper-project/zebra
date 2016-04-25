// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// testbench for prover_shuffle_v
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

`include "prover_shuffle_v.sv"

module prover_shuffle_v_test ();

localparam ngates = 15;
localparam plstages = 2;
localparam ngates_in = 1 << ($clog2(ngates) - 1);

integer rseed, i;
reg clk, rstb, en, trig;
reg [`F_NBITS-1:0] v_0_in [ngates_in-1:0];
reg [`F_NBITS-1:0] v_1_in [ngates_in-1:0];
reg [`F_NBITS-1:0] v_tau_in [ngates_in-1:0];
wire ready, ready_pulse;
wire [`F_NBITS-1:0] v_0 [ngates-1:0];
wire [`F_NBITS-1:0] v_1 [ngates-1:0];
wire [`F_NBITS-1:0] v_tau [ngates-1:0];

prover_shuffle_v
   #( .ngates       (ngates)
    , .plstages     (plstages)
    ) ishuffle
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en | trig)
    , .restart      (trig)
    , .v_0_in       (v_0_in)
    , .v_1_in       (v_1_in)
    , .v_tau_in     (v_tau_in)
    , .ready        (ready)
    , .ready_pulse  (ready_pulse)
    , .v_0          (v_0)
    , .v_1          (v_1)
    , .v_tau        (v_tau)
    );

initial begin
`ifdef SIMULATOR_IS_ICARUS
    $dumpfile("prover_shuffle_v_test.fst");
    $dumpvars;
    for (i = 0; i < ngates_in; i = i + 1) begin
        $dumpvars(0, v_0_in[i], v_1_in[i], v_tau_in[i]);
    end
    for (i = 0; i < ngates; i = i + 1) begin
        $dumpvars(0, v_0[i], v_1[i], v_tau[i]);
    end
`else
    $shm_open("prover_shuffle_v_test.shm");
    $shm_probe("ASCM");
`endif
    rseed = 1;
    set_inputs();
    clk = 0;
    rstb = 0;
    trig = 0;
    en = 0;
    #1 rstb = 1;
    clk = 1;
    #1 trig = 1;
    #2 trig = 0;
    #100 trig = 1;
    #2 trig = 0;
    #100 $finish;
end

`ALWAYS_FF @(posedge clk) begin
    en <= ready_pulse;
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task set_inputs;
begin
    for (i = 0; i < ngates_in; i = i + 1) begin
        v_0_in[i] = i;
        v_1_in[i] = 256 * i;
        v_tau_in[i] = 256 * 256 * i;
    end
end
endtask

task randomize_inputs;
begin
    for (i = 0; i < ngates_in; i = i + 1) begin
        v_0_in[i] = $random(rseed);
        v_0_in[i] = {v_0_in[i][31:0],32'b0} | $random(rseed);
        v_1_in[i] = $random(rseed);
        v_1_in[i] = {v_1_in[i][31:0],32'b0} | $random(rseed);
        v_tau_in[i] = $random(rseed);
        v_tau_in[i] = {v_tau_in[i][31:0],32'b0} | $random(rseed);
    end
end
endtask

endmodule
