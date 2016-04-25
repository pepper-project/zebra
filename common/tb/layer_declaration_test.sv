// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// test for gate specifications
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// This module is a test of how a particular level of a circuit can be
// conditionally generated using SystemVerilog's own conditional generation
// functionality.

// In this scheme, a compiler (e.g., Allspice's) produces a description of an
// arithmetic circuit whose execution we wish to verify. It then converts this
// description into a compact format which specifies, for each layer of the
// circuit, how many gates are at this layer, how many inputs are coming from
// the previous layer, whether each gate is mul or add, and which inputs are
// connected to each gate.

// The advantage of this approach over directly generating SystemVerilog
// for the desired gate configuration is that this gives a much narrower
// interface between the compiler and the implementation of the prover
// and corresponding circuit, meaning that the underlying implementation
// of the circuit can be changed without updating the compiler.
//
// If our target Verilog simulator were only NCVerilog, we could use more
// advanced parameter types (e.g., unpacked arrays of unpacked structs) which
// might make the generate functionality that processes each gate slightly
// prettier. Unfortunately, Icarus Verilog supports only packed parameters; so
// that means we have to turn our specifications into bit vectors and then
// work directly on those. And so it goes.

module test
   #( parameter ngates = 8
    , parameter ninputs = 8
    , parameter [ngates-1:0] gates_mul = 0
    , parameter ninbits = $clog2(ninputs)
    , parameter [(ninbits*ngates)-1:0] gates_in0 = 0
    , parameter [(ninbits*ngates)-1:0] gates_in1 = 0
   )();

genvar InCk;
generate
    for (InCk = 0; InCk < ngates; InCk = InCk + 1) begin: IGateCheck
        localparam gi0 = gates_in0[(InCk*ninbits) +: ninbits];
        localparam gi1 = gates_in1[(InCk*ninbits) +: ninbits];
        if (gi0 >= ninputs || gi1 >= ninputs) begin
            Illegal_input_declared_for_gate__must_be_less_than_ninputs __error__();
        end
    end
endgenerate

integer i;
initial begin
    $display("%h", ngates);
    $display("%h", ninputs);
    $display("%b", gates_mul);
    $display("%h", gates_in0);
    $display("%h", gates_in1);
    for (i = 0; i < ngates; i++) begin
        $display("%s: %d, %d", gates_mul[i] ? "mul" : "add"
                             , gates_in0[(i*ninbits) +: ninbits]
                             , gates_in1[(i*ninbits) +: ninbits]
                             );
    end
end

endmodule
      
module test_top ();
      
localparam ngates = 8;
localparam ninputs = 8;
localparam [ngates-1:0] gates_mul = 8'ha5;
localparam [(ngates*3)-1:0] gates_in0 =
    {3'h7, 3'h6, 3'h5, 3'h4, 3'h3, 3'h2, 3'h1, 3'h0};

localparam [(ngates*3)-1:0] gates_in1 =
    {3'h0, 3'h1, 3'h2, 3'h3, 3'h4, 3'h5, 3'h6, 3'h7};

test #( .ngates     (ngates)
      , .ninputs    (ninputs)
      , .gates_mul  (gates_mul)
      , .gates_in0  (gates_in0)
      , .gates_in1  (gates_in1)
      ) itest
      ();

endmodule
