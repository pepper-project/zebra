// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// top level for pergate functionality
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// Each gate in a computation's underlying arithmetic circuit contributes
// to the values sent from Prover to Verifier in each round of the sumcheck
// protocol.
//
// This module captures all of the functionality necessary to compute one
// gate's contribution to this value.
//
// This version of the module computes some values sequentially rather
// than in parallel, which adds O(1) time in each round but saves several
// multipliers.

`ifndef __module_pergate_compute
`include "simulator.v"
`include "field_arith_defs.v"
`include "gatefn_defs.v"
`include "pergate_compute_am012.sv"
`include "pergate_compute_am_fj.sv"
`include "pergate_compute_gatefn_seq.sv"
module pergate_compute
   #( parameter [`GATEFN_BITS-1:0] gate_fn = 0
    , parameter nidbits = 9 // # of bits in {in1_id, in0_id, gate_id} vector --- NOTE bit order!
    , parameter [nidbits-1:0] id_vec = 0 // {in1_id, in0_id, gate_id} vector
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 restart     // restarting this level
    , input                 precomp     // precomputation --- only compute addmul

    , input  [`F_NBITS-1:0] tau
    , input  [`F_NBITS-1:0] m_tau_p1

    , input                 mux_sel
    , input  [`F_NBITS-1:0] vin0 [2:0]
    , input  [`F_NBITS-1:0] vin1 [2:0]

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] gate_out [2:0]
    );

// ready wires for computation units
wire [3:0] mod_ready;

// start --- edge detect on enable
reg en_dly;
wire start = en & ~en_dly & (&mod_ready);
// need to wait one cycle for id_reg update before kicking off computations
reg start_dly;
reg precomp_reg;
reg restart_reg;

// ready outputs
assign ready = &(mod_ready) & ~start;
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

// NOTE regarding precomp
//
// precomp should be set for the first n_gate_id_bits - 1 cycles.
// Why one less? Because on the final cycle in which we're precomputing
// add or mul, we've now got to compute V(0), V(1), and V(2).
//
// This is related to the reason that we apply id_reg[0] for both compute_addmul
// and compute_am012: by the time compute_am012 has kicked off, id_reg has
// been shifted to the right by 1 bit, meaning that compute_am012 is working
// on the "next" id bit.
//
// Example:
//
// id_vec = 6'b01_01_01; // (each id is 2 bits)
//
// First cycle: id_reg[0] == 1.
// Second cycle: id_reg[0] == 0, and after compute_addmul is done computing,
// we've finished precomputing the values of add~ or mul~, so now we should
// immediately start evaluating am012.
//
// (Note that by the time compute_am012's enable signal triggers, id_reg[0] == 1.)

// gate ID register
// shift out LSB every time we start a computation
reg [nidbits-1:0] id_reg;
reg [nidbits-1:0] id_next;

`ALWAYS_COMB begin
    id_next = id_reg;

    if (start & restart) begin
        // when restarting, reset prior to start_dly so that id_reg is
        // correct when compute_addmul starts executing
        id_next = id_vec;
    end else if (start_dly) begin
        // otherwise, shift id_reg right one bit *after* compute_addmul starts
        id_next = {1'b0,id_reg[nidbits-1:1]};
    end
end

// eval addmul at 0, 1, and 2
wire [`F_NBITS-1:0] addmul_eval;
wire addmul_ready_pulse;
wire [`F_NBITS-1:0] addmul [2:0];
pergate_compute_am012 iam012
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (addmul_ready_pulse & ~precomp_reg) // only run am012 if we're not precomputing
    , .gate_id_bit  (id_reg[0]) // NOTE: see above in explanation about precomp.
    , .addmul_in    (addmul_eval)
    , .ready_pulse  ()
    , .ready        (mod_ready[1])
    , .addmul       (addmul)
    );

// *** NOTE ***
//
// Because we start compute_gatefn and compute_addmul at the same time,
// and because prover_layer waits to start pergate_compute until compute_v is
// done, in the worst case we add an additional multiplier's worth of delay.
// In the ideal case, compute_addmul and compute_am012 can run at the same
// time as compute_v, then compute_gatefn runs, and finally compute_fj runs.
//
// Currently, the total delay is
//    2 x mul + 2 x add (from compute_v)
//    1 x mul + 1 x add (from compute_addmul and compute_am012 in series)
//                      (this is in parallel with compute_gatefn)
//    1 x mul           (this is from compute_fj)
//
// In the best case, the total delay is
//    2 x mul + 2 x add (from compute_v)
//                      (this is in parallel with compute_addmul and compute_am012)
//    1 x mul OR add    (this is from compute_gatefn)
//    1 x mul           (this is from compute_fj)
//
// So in principle we could speed up this operation by either 1 mul or 1 add
// depending on what type of gate this is. Expected overall savings is 1 add
// delay since all the pergate_compute blocks execute in parallel and all must
// finish before the state machine can continue.
//
// TODO: revisit above --- a relatively minor modification, though
//       it will also necessitate changes to the prover_layer state machine,
//       specifically, to kick off pergate_compute and compute_v at the same
//       time rather than in sequence.
//
// compute gate function
wire [`F_NBITS-1:0] gatefn [2:0];
pergate_compute_gatefn_seq
   #( .gate_fn      (gate_fn)
    ) igatefn
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (start_dly & ~precomp_reg)          // only run gatefn if we're not precomputing
    , .mux_sel      (mux_sel)
    , .in0          (vin0)
    , .in1          (vin1)
    , .ready        (mod_ready[2])
    , .gatefn       (gatefn)
    );

// compute addmul and fj contributions
wire gate_am012_rdy = &(mod_ready[2:0]);
reg gate_am012_rdy_dly;
wire en_fj = gate_am012_rdy & ~gate_am012_rdy_dly;
pergate_compute_am_fj iamfj
    ( .clk              (clk)
    , .rstb             (rstb)
    , .en_am            (start_dly)
    , .restart          (restart_reg)
    , .gate_id_bit      (id_reg[0])
    , .tau              (tau)
    , .m_tau_p1         (m_tau_p1)
    , .ready_pulse_am   (addmul_ready_pulse)
    , .ready_am         (mod_ready[0])
    , .addmul_eval      (addmul_eval)
    , .en_fj            (en_fj & ~precomp_reg)
    , .gatefn           (gatefn)
    , .addmul           (addmul)
    , .ready_fj         (mod_ready[3])
    , .fj               (gate_out)
    );

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        id_reg <= id_vec;
        ready_dly <= 1;
        en_dly <= 1;
        start_dly <= 0;
        gate_am012_rdy_dly <= 1;
        precomp_reg <= 0;
        restart_reg <= 0;
    end else begin
        id_reg <= id_next;
        ready_dly <= ready;
        en_dly <= en;
        start_dly <= start;
        gate_am012_rdy_dly <= gate_am012_rdy;
        if (start) begin
            // update precomp and restart each time we begin a computation
            precomp_reg <= precomp;
            restart_reg <= restart;
        end else begin
            precomp_reg <= precomp_reg;
            restart_reg <= restart_reg;
        end
    end
end

endmodule
`define __module_pergate_compute
`endif // __module_pergate_compute
