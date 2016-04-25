// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// compute evals of H(gamma(.)) for one gate
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// When computing H(gamma(.)), each gate needs to choose tau or 1-tau
// depending on the current bit of the gate id. This block tracks the
// gate ID over the course of H(gamma(.)) evaluations, and chooses
// the appropriate multiplicand each round.

`ifndef __module_prover_compute_h_elem
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_multiplier.sv"
module prover_compute_h_elem
   #( parameter nidbits = 3
    , parameter [nidbits-1:0] gate_id = 0
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 restart
    , input                 done    // when done is true, id reg is shifted after mult is done

    , input  [`F_NBITS-1:0] v_in
    , input  [`F_NBITS-1:0] v_q

    , input  [`F_NBITS-1:0] tau
    , input  [`F_NBITS-1:0] m_tau_p1

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] v_data
    );

// edge detect for enable
reg restart_dly;
wire restart_pulse = restart & ~restart_dly;

// register for holding ID
reg [nidbits-1:0] id_reg, id_next;

// multiplier hookup
wire [`F_NBITS-1:0] mult_a = restart ? v_in : v_q;
wire [`F_NBITS-1:0] mult_b = id_reg[0] ? tau : m_tau_p1;

field_multiplier imul
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en)
    , .a            (mult_a)
    , .b            (mult_b)
    , .ready_pulse  (ready_pulse)
    , .ready        (ready)
    , .c            (v_data)
    );

`ALWAYS_COMB begin
    id_next = id_reg;
    // update id register
    if (restart_pulse) begin
        // when we get a restart pulse, reset the gate ID
        id_next = gate_id;
    end else if (done & ready_pulse) begin
        // when we have finished computing the last gamma value
        // for this bit of the gate ID, shift the gate ID reg
        id_next = {1'b0, id_reg[nidbits-1:1]};
    end
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        id_reg <= gate_id;
        restart_dly <= 1;
    end else begin
        id_reg <= id_next;
        restart_dly <= restart;
    end
end

endmodule
`define __module_prover_compute_h_elem
`endif // __module_prover_compute_h_elem
