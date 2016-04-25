// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// testbench for pergate_compute
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

`include "pergate_compute.sv"

module pergate_compute_test ();

localparam nidbits = 9;
localparam precomp_dfl = 9'o003;

integer rseed, i;
reg [`F_NBITS-1:0] tau, m_tau_p1;
reg [`F_NBITS-1:0] vin0_0 [2:0], vin0_1 [2:0], vin1_0, vin1_1;
wire [`F_NBITS-1:0] gate_out_0 [2:0], gate_out_1 [2:0];
reg clk, rstb, trig;
wire [1:0] unit_ready;
wire all_ready = &(unit_ready);
reg all_ready_dly;
wire en_units = all_ready & ~all_ready_dly;
reg en_units_dly;
reg [8:0] precomp;

pergate_compute
   #( .is_mul       (1)
    , .nidbits      (nidbits)
    , .id_vec       (9'o252)
    ) comp_mul
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en_units_dly)
    , .restart      (trig)
    , .precomp      (precomp[0])
    , .tau          (tau)
    , .m_tau_p1     (m_tau_p1)
    , .vin0         (vin0_0)
    , .vin1         (vin1_0)
    , .ready_pulse  ()
    , .ready        (unit_ready[0])
    , .gate_out     (gate_out_0)
    );

pergate_compute
   #( .is_mul       (0)
    , .nidbits      (nidbits)
    , .id_vec       (9'o525)
    ) comp_add
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en_units_dly)
    , .restart      (trig)
    , .precomp      (precomp[0])
    , .tau          (tau)
    , .m_tau_p1     (m_tau_p1)
    , .vin0         (vin0_1)
    , .vin1         (vin1_1)
    , .ready_pulse  ()
    , .ready        (unit_ready[1])
    , .gate_out     (gate_out_1)
    );

initial begin
`ifdef SIMULATOR_IS_ICARUS
    $dumpfile("pergate_compute_test.fst");
    $dumpvars;
    for (i = 0; i < 3; i = i + 1) begin
        $dumpvars(0, vin0_0[i], vin0_1[i], gate_out_0[i], gate_out_1[i]);
        $dumpvars(0, comp_mul.addmul[i], comp_mul.gatefn[i], comp_mul.gate_out[i]);
        $dumpvars(0, comp_add.addmul[i], comp_add.gatefn[i], comp_add.gate_out[i]);
    end
`else
    $shm_open("prover_compute_test.shm");
    $shm_probe("ASCM");
`endif
    rseed = 1;
    all_ready_dly = 1;
    randomize_tau();
    randomize_inputs();
    clk = 0;
    rstb = 0;
    trig = 0;
    en_units_dly = 0;
    precomp = precomp_dfl;
    #1 rstb = 1;
    clk = 1;
    #1 trig = 1;
    #4 trig = 0;
    #342 trig = 1;
    #4 trig = 0;
    #360 $finish;
end

`ALWAYS_FF @(posedge clk) begin
    all_ready_dly <= all_ready;
    en_units_dly <= en_units | trig;
    precomp <= trig ? precomp_dfl : (en_units_dly ? {1'b0,precomp[8:1]} : precomp);
    if (en_units) begin
        //randomize_tau();
        if (trig) begin
            //randomize_inputs();
        end
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end

task randomize_tau;
begin
    randomize_single_value(tau);
    m_tau_p1 = $f_add(~tau, `F_Q_P2_MI);
end
endtask

task randomize_inputs;
    integer i;
begin
    randomize_single_value(vin1_0);
    randomize_single_value(vin1_1);
    for (i = 0; i < 3; i = i + 1) begin
        randomize_single_value(vin0_0[i]);
        randomize_single_value(vin0_1[i]);
    end
end
endtask

task randomize_single_value;
    output [`F_NBITS-1:0] v;
begin
    v = $random(rseed);
    v = {v[31:0],32'b0} | $random(rseed);
end
endtask

endmodule
