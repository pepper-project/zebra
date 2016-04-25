// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// testbench for prover_compute_v
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

`include "prover_compute_v.sv"

module prover_compute_v_test ();

localparam ngates = 43;
localparam ngates_out = 1 << ($clog2(ngates) - 1);

integer rseed, i;
reg clk, rstb, en, trig;
reg [`F_NBITS-1:0] v_in [ngates-1:0];
reg [`F_NBITS-1:0] tau, m_tau_p1;
wire ready, ready_pulse;
wire [`F_NBITS-1:0] v_0 [ngates_out-1:0], v_1 [ngates_out-1:0], v_tau [ngates_out-1:0];

prover_compute_v
   #( .ngates       (ngates)
    ) icompute
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en | trig)
    , .restart      (trig)
    , .skip012      (1'b0)
    , .v_in         (v_in)
    , .tau          (tau)
    , .m_tau_p1     (m_tau_p1)
    , .ready_pulse  (ready_pulse)
    , .ready        (ready)
    , .v_0          (v_0)
    , .v_1          (v_1)
    , .v_tau        (v_tau)
    );

initial begin
    $dumpfile("prover_compute_v_test.vcd");
    $dumpvars;
    rseed = 1;
    randomize_tau();
    for (i = 0; i < ngates; i = i + 1) begin
        v_in[i] = $random(rseed);
        v_in[i] = {v_in[i][31:0],32'b0} | $random(rseed);
    end
    clk = 0;
    rstb = 0;
    trig = 0;
    en = 0;
    #1 rstb = 1;
    clk = 1;
    #2 trig = 1;
    #2 trig = 0;
    #1000 $finish;
end

`ALWAYS_FF @(posedge clk) begin
    en <= ready_pulse;
    if (ready_pulse) begin
        randomize_tau();
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task randomize_tau;
begin
    tau = $random(rseed);
    tau = {tau[31:0],32'b0} | $random(rseed);
    m_tau_p1 = $f_add(~tau, `F_Q_P2_MI);
end
endtask

endmodule
