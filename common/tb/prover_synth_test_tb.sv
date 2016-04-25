// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// testbench for prover_synth_test - generate vcd file, show runtime
// (C) 2015 Riad S. Wahby

`include "prover_synth_test.sv"
module prover_synth_test_tb ();

localparam ngates = `PROVER_SYNTH_TEST_N;
localparam ninputs = `PROVER_SYNTH_TEST_N;
localparam ninbits = $clog2(ninputs);

integer i, rseed, curtime, inittime;
reg clk, rstb, en, restart, comp_w0, finish;

reg [`F_NBITS-1:0] v_in [ninputs-1:0];
reg [`F_NBITS-1:0] tau;
wire [`F_NBITS-1:0] w0 [ninbits-1:0];
wire [`F_NBITS-1:0] buf_data [ninbits:0];
wire ready_pulse, w0_ready, w0_ready_pulse;
wire [1:0] ready_code;

prover_synth_test itest
    ( .clk              (clk)
    , .rstb             (rstb)
    , .en               (en)
    , .restart          (restart)
    , .v_in             (v_in)
    , .tau              (tau)
    , .comp_w0          (comp_w0)
    , .tau_w0           (tau)
    , .w0               (w0)
    , .w0_ready_pulse   (w0_ready_pulse)
    , .w0_ready         (w0_ready)
    , .ready_pulse      (ready_pulse)
    , .ready_code       (ready_code)
    , .buf_data         (buf_data)
    );

initial begin
    $dumpfile("prover_synth_test.vcd");
    $dumpvars;
    rseed = 1;
    randomize_tau();
    randomize_inputs();
    clk = 0;
    rstb = 0;
    en = 0;
    finish = 0;
    comp_w0 = 0;
    restart = 1;
    #1 rstb = 1;
    clk = 1;

    #3 $display("\nStarting sumcheck.");
    inittime = $time;
    curtime = $time;
    en = 1;
    restart = 1;
    #2 en = 0;
    restart = 0;
end

always @(posedge clk) begin
    if (ready_pulse) begin
        $display("*** Round complete. elapsed cycles %d", ($time - curtime)/2);
        curtime = $time;
        randomize_tau();
        case (ready_code)
            2'b00, 2'b01: begin
                en <= 1;
                comp_w0 <= 0;
            end

            default: begin
                en <= 0;
                comp_w0 <= 1;
            end
        endcase
    end else begin
        en <= 0;
        comp_w0 <= 0;
    end

    if (w0_ready_pulse) begin
        $display("*********\nFinished %d sumcheck rounds in %d cycles.\n*********", 2*ninbits + $clog2(ngates), ($time - inittime)/2);
        finish <= 1;
    end

    if (finish) begin
        $finish;
    end
end

always @(clk) begin
    clk <= #1 ~clk;
end

task randomize_inputs;
    integer i;
begin
    for (i = 0; i < ninputs; i = i + 1) begin
        randomize_single_value(v_in[i]);
    end
end
endtask

task randomize_tau;
begin
    randomize_single_value(tau);
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
// vim: syntax=verilog_systemverilog
