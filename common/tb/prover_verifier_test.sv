// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// Test of full verifier-prover interaction for a simple circuit

/*
* NOTE: to use this testbench, you will need to run a verifier
* process. Point the verifier process to pws/simple.pws with
* 2nd argument 1 (i.e., two horizontal repeats).
*/

`include "computation_layer.sv"
`include "prover_layer.sv"
`include "ringbuf_simple.sv"
`include "verifier_interface.sv"
`include "verifier_interface_w0.sv"

module prover_verifier_test ();

localparam nlayers = 1;
localparam ngates = 16;
localparam ninputs = 16;
localparam [15:0] gates_mul = 16'b1010101010101010;
localparam [63:0] gates_in0 = {4'hf, 4'he, 4'hd, 4'hc, 4'hb, 4'ha, 4'h9, 4'h8, 4'h7, 4'h6, 4'h5, 4'h4, 4'h3, 4'h2, 4'h1, 4'h0};
localparam [63:0] gates_in1 = {4'h8, 4'hf, 4'he, 4'hd, 4'hc, 4'hb, 4'ha, 4'h9, 4'h0, 4'h7, 4'h6, 4'h5, 4'h4, 4'h3, 4'h2, 4'h1};

/*
localparam ngates = 8;
localparam ninputs = 8;
localparam [7:0] gates_mul = 8'b10101010;
localparam [23:0] gates_in0 = {3'o7, 3'o6, 3'o5, 3'o4, 3'o3, 3'o2, 3'o1, 3'o0};
localparam [23:0] gates_in1 = {3'o0, 3'o7, 3'o6, 3'o5, 3'o4, 3'o3, 3'o2, 3'o1};
*/

localparam shuf_plstages = 2;
localparam ninbits = $clog2(ninputs);
localparam nhpoints = $clog2(ninputs) + 1;
localparam ngbits = $clog2(ngates);

reg [31:0] id;
integer i, rseed;
reg clk, rstb, en_cmt, en_computation, comp_w0_reg;

// interface to verifier
wire ready_pulse, en_layer, restart_layer, comp_w0, w0_done_pulse, w0_ready_in, v_ready_pulse, v_ready, w0_ready_pulse;
wire [`F_NBITS-1:0] tau;
wire [1:0] ready_code;
wire [`F_NBITS-1:0] layer_data [nhpoints-1:0];
wire [`F_NBITS-1:0] w0 [ngbits-1:0];
verifier_interface
   #( .ninputs      (ninputs)
    , .ngates       (ngates)
    , .layer_num    (0)
    ) iintf
    ( .clk                  (clk)
    , .rstb                 (rstb)
    , .en                   (en_cmt)
    , .id                   (id)
    , .layer_ready_pulse    (ready_pulse)
    , .layer_ready_code     (ready_code)
    , .layer_data           (layer_data)
    , .en_layer             (en_layer)
    , .restart_layer        (restart_layer)
    , .tau                  (tau)
    , .comp_w0              (comp_w0)
    , .w0_done_pulse        (w0_done_pulse)
    , .w0_ready_in          (w0_ready_in)
    , .w0                   (w0)
    , .w0_done_in           (1'b1)
    , .ready_pulse          (v_ready_pulse)
    , .ready                (v_ready)
    );

// get w0 directly from verifier for output layer
verifier_interface_w0
   #( .ngates       (ngates)
    ) iintfw0
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (comp_w0)
    , .id           (id)
    , .w0_ready     (w0_ready_in)
    , .w0           (w0)
    );

// buffer to hold prover_layer's outputs
wire f_wren, p_wren;
wire buf_en = f_wren | p_wren;
wire [`F_NBITS-1:0] fp_data;
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
    , .q_all        (layer_data)
    );

// instantiation of prover for output layer
reg [`F_NBITS-1:0] v_in [ninputs-1:0];
prover_layer
   #( .ngates           (ngates)
    , .ninputs          (ninputs)
    , .gates_mul        (gates_mul)
    , .gates_in0        (gates_in0)
    , .gates_in1        (gates_in1)
    , .shuf_plstages    (shuf_plstages)
    ) iprv
    ( .clk              (clk)
    , .rstb             (rstb)
    , .en               (en_layer)
    , .restart          (restart_layer)
    , .v_in             (v_in)
    , .tau              (tau)
    , .f_wren           (f_wren)
    , .p_wren           (p_wren)
    , .fp_data          (fp_data)
    , .comp_w0          (comp_w0_reg)
    , .tau_w0           (61'b1)
    , .w0               ()
    , .w0_ready_pulse   (w0_ready_pulse)
    , .w0_ready         ()
    , .ready_pulse      (ready_pulse)
    , .ready_code       (ready_code)
    );

// instantiation of output layer itself
wire comp_ready;
wire [`F_NBITS-1:0] v_out [ngates-1:0];
computation_layer
   #( .ngates           (ngates)
    , .ninputs          (ninputs)
    , .gates_mul        (gates_mul)
    , .gates_in0        (gates_in0)
    , .gates_in1        (gates_in1)
    ) icomp
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en_computation)
    , .v_in         (v_in)
    , .ready_pulse  ()
    , .ready        (comp_ready)
    , .v_out        (v_out)
    );

initial begin
`ifdef SIMULATOR_IS_ICARUS
    $dumpfile("prover_verifier_test.fst");
    $dumpvars;
    for (i = 0; i < ninputs; i = i + 1) begin
        $dumpvars(0, v_in[i]);
    end
    for (i = 0; i < ngates; i = i + 1) begin
        $dumpvars(0, v_out[i]);
    end
    for (i = 0; i < nhpoints; i = i + 1) begin
        $dumpvars(0, layer_data[i]);
    end
`else
    $shm_open("prover_verifier_test.shm");
    $shm_probe("ASCM");
`endif
    for (i = 0; i < ninputs; i = i + 1) begin
        v_in[i] = 0;
    end
    clk = 0;
    rstb = 0;
    en_cmt = 0;
    en_computation = 0;
    comp_w0_reg = 0;
    #1 rstb = 1;
    clk = 1;
    id = $cmt_init(ninputs, nlayers + 1); // args are: max width of any layer, including inputs ; and #layers + 1
    $cmt_request(id, `CMT_INPUT, v_in, ninputs);
    #3 en_computation = 1;
    #2 en_computation = 0;
    #18 $cmt_send(id, `CMT_OUTPUT, v_out, ngates);

    #2 en_cmt = 1;
    #2 en_cmt = 0;
end

`ALWAYS_FF @(posedge clk) begin
    if (v_ready_pulse) begin
        comp_w0_reg <= 1;
    end

    if (w0_ready_pulse) begin
        #2 $finish;
    end
end

`ALWAYS_FF @(clk) begin
    clk <= #1 ~clk;
end


endmodule
