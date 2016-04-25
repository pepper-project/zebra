// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// testbench for prover_layer
// (C) 2015 Riad S. Wahby

`include "prover_layer.sv"
`include "ringbuf_simple.sv"

module prover_layer_test ();

/*
localparam ngates = 8;
localparam ninputs = 8;
localparam [7:0] gates_mul = 8'b10101010;
localparam [23:0] gates_in0 = {3'o7, 3'o6, 3'o5, 3'o4, 3'o3, 3'o2, 3'o1, 3'o0};
localparam [23:0] gates_in1 = {3'o0, 3'o7, 3'o6, 3'o5, 3'o4, 3'o3, 3'o2, 3'o1};
*/

localparam ngates = 110;
localparam ninputs = 100;
localparam [109:0] gates_mul = 110'b11111100000111111000001111110000011111100000111111000001111110000011111100000111111000001111110000011111100000;
localparam [769:0] gates_in0 = {7'h5d, 7'h5c, 7'h5d, 7'h5c, 7'h5b, 7'h5a, 7'h60, 7'h63, 7'h5a, 7'h62, 7'h5e, 7'h53, 7'h52, 7'h53, 7'h52, 7'h51, 7'h50, 7'h56, 7'h59, 7'h50, 7'h58, 7'h54, 7'h49, 7'h48, 7'h49, 7'h48, 7'h47, 7'h46, 7'h4c, 7'h4f, 7'h46, 7'h4e, 7'h4a, 7'h3f, 7'h3e, 7'h3f, 7'h3e, 7'h3d, 7'h3c, 7'h42, 7'h45, 7'h3c, 7'h44, 7'h40, 7'h35, 7'h34, 7'h35, 7'h34, 7'h33, 7'h32, 7'h38, 7'h3b, 7'h32, 7'h3a, 7'h36, 7'h2b, 7'h2a, 7'h2b, 7'h2a, 7'h29, 7'h28, 7'h2e, 7'h31, 7'h28, 7'h30, 7'h2c, 7'h21, 7'h20, 7'h21, 7'h20, 7'h1f, 7'h1e, 7'h24, 7'h27, 7'h1e, 7'h26, 7'h22, 7'h17, 7'h16, 7'h17, 7'h16, 7'h15, 7'h14, 7'h1a, 7'h1d, 7'h14, 7'h1c, 7'h18, 7'hd, 7'hc, 7'hd, 7'hc, 7'hb, 7'ha, 7'h10, 7'h13, 7'ha, 7'h12, 7'he, 7'h3, 7'h2, 7'h3, 7'h2, 7'h1, 7'h0, 7'h6, 7'h9, 7'h0, 7'h8, 7'h4};
localparam [769:0] gates_in1 = {7'h61, 7'h5f, 7'h60, 7'h5e, 7'h61, 7'h5f, 7'h63, 7'h63, 7'h63, 7'h63, 7'h5b, 7'h57, 7'h55, 7'h56, 7'h54, 7'h57, 7'h55, 7'h59, 7'h59, 7'h59, 7'h59, 7'h51, 7'h4d, 7'h4b, 7'h4c, 7'h4a, 7'h4d, 7'h4b, 7'h4f, 7'h4f, 7'h4f, 7'h4f, 7'h47, 7'h43, 7'h41, 7'h42, 7'h40, 7'h43, 7'h41, 7'h45, 7'h45, 7'h45, 7'h45, 7'h3d, 7'h39, 7'h37, 7'h38, 7'h36, 7'h39, 7'h37, 7'h3b, 7'h3b, 7'h3b, 7'h3b, 7'h33, 7'h2f, 7'h2d, 7'h2e, 7'h2c, 7'h2f, 7'h2d, 7'h31, 7'h31, 7'h31, 7'h31, 7'h29, 7'h25, 7'h23, 7'h24, 7'h22, 7'h25, 7'h23, 7'h27, 7'h27, 7'h27, 7'h27, 7'h1f, 7'h1b, 7'h19, 7'h1a, 7'h18, 7'h1b, 7'h19, 7'h1d, 7'h1d, 7'h1d, 7'h1d, 7'h15, 7'h11, 7'hf, 7'h10, 7'he, 7'h11, 7'hf, 7'h13, 7'h13, 7'h13, 7'h13, 7'hb, 7'h7, 7'h5, 7'h6, 7'h4, 7'h7, 7'h5, 7'h9, 7'h9, 7'h9, 7'h9, 7'h1};
localparam shuf_plstages = 2;
localparam ninbits = $clog2(ninputs);

integer i, rseed, curtime, inittime;

reg clk, rstb, en, restart, comp_w0, finish;

reg [`F_NBITS-1:0] v_in [ninputs-1:0];
reg [`F_NBITS-1:0] tau;
wire [`F_NBITS-1:0] w0 [ninbits-1:0];

wire f_wren;
wire p_wren;
wire [`F_NBITS-1:0] fp_data;

wire ready_pulse, w0_ready, w0_ready_pulse;
wire [1:0] ready_code;

// ringbuf to hold output from each round of sumcheck
localparam nhpoints = $clog2(ninputs) + 1;   // # of points in H(gamma(.))
wire buf_en = f_wren | p_wren;
wire [`F_NBITS-1:0] buf_data [nhpoints-1:0];
ringbuf_simple
   #( .nbits        (`F_NBITS)
    , .nwords       (nhpoints)
    ) ibuf
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (buf_en)
    , .wren         (buf_en)
    , .d            (fp_data)
    , .q            ()
    , .q_all        (buf_data)
    );

// one layer of the prover
prover_layer
   #( .ngates           (ngates)
    , .ninputs          (ninputs)
    , .gates_mul        (gates_mul)
    , .gates_in0        (gates_in0)
    , .gates_in1        (gates_in1)
    , .shuf_plstages    (shuf_plstages)
    ) iprv
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en)
    , .restart      (restart)
    , .v_in         (v_in)
    , .tau          (tau)
    , .f_wren       (f_wren)
    , .p_wren       (p_wren)
    , .fp_data      (fp_data)
    , .comp_w0      (comp_w0)
    , .tau_w0       (tau)
    , .w0           (w0)
    , .w0_ready_pulse (w0_ready_pulse)
    , .w0_ready     (w0_ready)
    , .ready_pulse  (ready_pulse)
    , .ready_code   (ready_code)
    );

localparam ngates_unshuf = 1 << ($clog2(ninputs) - 1);
localparam naddgates = (ninputs > ngates) ? ninputs : ngates;
initial begin
`ifdef SIMULATOR_IS_ICARUS
    // this is ludicrous. Why oh why can't Icarus just dump all arrays by
    // default?
    $dumpfile("prover_layer_test.fst");
    $dumpvars;
    for (i = 0; i < ninputs; i = i + 1) begin
        $dumpvars(0, v_in[i], iprv.v_0_shuf[i], iprv.v_1_shuf[i], iprv.v_tau_shuf[i], iprv.h_data[i]);
    end
    for (i = 0; i < 3; i = i + 1) begin
        $dumpvars(0, iprv.GComp[0].vin0[i]);
    end
    for (i = 0; i < nhpoints; i = i + 1) begin
        $dumpvars(0, buf_data[i]);
    end
    for (i = 0; i < ngates_unshuf; i = i + 1) begin
        $dumpvars(0, iprv.v_0_unshuf[i], iprv.v_1_unshuf[i], iprv.v_tau_unshuf[i]);
    end
    for (i = 0; i < naddgates; i = i + 1) begin
        $dumpvars(0, iprv.addt_in[i]);
    end
    for (i = 0; i < 4; i = i + 1) begin
        $dumpvars(0, iprv.AddHookup[0].g_add_in[i]);
    end
    for (i = 0; i < 4; i = i + 1) begin
        $dumpvars(0, iprv.AddHookup[1].g_add_in[i]);
    end
    for (i = 0; i < 4; i = i + 1) begin
        $dumpvars(0, iprv.AddHookup[2].g_add_in[i]);
    end
    for (i = 0; i < 4; i = i + 1) begin
        $dumpvars(0, iprv.AddHookup[3].g_add_in[i]);
    end
    for (i = 0; i < 4; i = i + 1) begin
        $dumpvars(0, iprv.AddHookup[4].g_add_in[i]);
    end
    for (i = 0; i < 4; i = i + 1) begin
        $dumpvars(0, iprv.AddHookup[5].g_add_in[i]);
    end
    for (i = 0; i < 4; i = i + 1) begin
        $dumpvars(0, iprv.AddHookup[6].g_add_in[i]);
    end
    for (i = 0; i < 4; i = i + 1) begin
        $dumpvars(0, iprv.AddHookup[7].g_add_in[i]);
    end
    for (i = 0; i < ninbits; i = i + 1) begin
        $dumpvars(0, w0[i], iprv.w2_m_w1_q_all[i], iprv.w1_q_all[i]);
    end
`else
    $shm_open("prover_layer_test.shm");
    $shm_probe("ASCM");
`endif
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

`ALWAYS_FF @(posedge clk) begin
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
        $display("*********\nFinished %d sumcheck rounds in %d cycles.\n(%f mult equivs).\n*********", 2*ninbits + $clog2(ngates), ($time - inittime)/2, ($time - inittime)/14);
        #10 $finish;
    end
end

`ALWAYS_FF @(clk) begin
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
