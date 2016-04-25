// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// testbench for prover_compute_h
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

`include "prover_compute_h.sv"
module prover_compute_h_test ();

localparam ngates = 16;

integer rseed, i;
wire ready, ready_pulse;
reg clk, rstb, en, trig, restart;
reg [`F_NBITS-1:0] neg_w1, w2;
reg [`F_NBITS-1:0] v_evals [ngates-1:0];

prover_compute_h
   #( .ngates       (ngates)
    ) icompute
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en | trig)
    , .restart      (restart)
    , .v_in         (v_evals)
    , .m_w1         (neg_w1)
    , .w2           (w2)
    , .ready_pulse  (ready_pulse)
    , .ready        (ready)
    , .p_rden       (1'b0)
    , .p_out        ()
    );

initial begin
`ifdef SIMULATOR_IS_ICARUS
    $dumpfile("prover_compute_h_test.fst");
    $dumpvars;
    for (i = 0; i < ngates; i = i + 1) begin
        $dumpvars(0, v_evals[i], icompute.v_data[i], icompute.v_q[i]);
    end
`else
    $shm_open("prover_shuffle_v_test.shm");
    $shm_probe("ASCM");
`endif
    rseed = 1000;
    clk = 0;
    rstb = 0;
    en = 0;
    trig = 0;
    restart = 1;
    randomize_w1_w2();
    for (i = 0; i < ngates; i = i + 1) begin
        v_evals[i] = $random(rseed);
        v_evals[i] = {v_evals[i][31:0],32'b0} | $random(rseed);
    end

    #1 clk = 1;
    #1 rstb = 1;
    #2 trig = 1;
    #2 trig = 0;
    #10000 $finish;
end

`ALWAYS_FF @(posedge clk) begin
    en <= ready_pulse;
    if (ready_pulse) begin
        restart <= 0;
        randomize_w1_w2();
    end
end

task randomize_w1_w2;
begin
    neg_w1 = $random(rseed);
    neg_w1 = {neg_w1[31:0],32'b0} | $random(rseed);
    w2 = $random(rseed);
    w2 = {w2[31:0],32'b0} | $random(rseed);
end
endtask

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

endmodule
