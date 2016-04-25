// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// CMT prover for one layer of an arithmetic circuit
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// This module comprises one layer of a CMT prover pipeline.
//
// The parameters to this module specify
//
//   (1) ngates : number of gates in this layer of the circuit
//
//   (2) ninputs : number of inputs to this layer (i.e., # gates in previous layer)
//
//   (3) gates_fn : vector of bits indicating the function of each gate (see computation_gatefn)
//
//   (4) gates_in0 : vector of bits indicating, for each gate, which in0 it should take
//
//   (5) gates_in1 : vector of bits indicating, for each gate, which in1 it should take
//
//   (6) shuf_plstages : number of stages between pipeline regs in prover_shuffle_v.
//                       (0 disables pipelining.)
//
// NOTE: **do not** override ninbits. This value must be a parameter to make
//       NCVerilog happy, but things will break if you override the default.

`ifndef __module_prover_layer
`include "simulator.v"
`include "field_arith_defs.v"
`include "gatefn_defs.v"
`include "field_multiplier.sv"
`include "field_negate.sv"
`include "field_one_minus.sv"
`ifndef USE_PERGATE_SEQ
`include "pergate_compute.sv"
`else
`include "pergate_compute_seq.sv"
`endif
`include "prover_adder_tree_pl.sv"
`include "prover_compute_h.sv"
`include "prover_compute_v.sv"
`include "prover_compute_w0.sv"
`include "prover_shuffle_v.sv"
`include "ringbuf_simple.sv"
module prover_layer
   #( parameter ngates = 8                      // # of gates at this layer of the ckt
    , parameter ninputs = 8                     // # of inputs (# gates at previous layer)
    , parameter nmuxsels = 1                    // number of entries in mux_sel

    , parameter [`GATEFN_BITS*ngates-1:0] gates_fn = 0  // function of each gate

    , parameter ninbits = $clog2(ninputs)       // lg(ninputs) -- DO NOT OVERRIDE
    , parameter nmuxbits = $clog2(nmuxsels)     // DO NOT OVERRIDE

    , parameter [(ninbits*ngates)-1:0] gates_in0 = 0    // vector specifying each gate's input #0
    , parameter [(ninbits*ngates)-1:0] gates_in1 = 0    // vector specifying each gate's input #1
    , parameter [(ngates*nmuxbits)-1:0] gates_mux = 0   // which gate goes to which mux_sel input?

    , parameter shuf_plstages = 0               // # stages between pipeline regs in shuffle
   )( input                 clk
    , input                 rstb

    , input                 en                  // run one round of sumcheck
    , input                 restart             // start new sumcheck

                                                // input data
    , input  [`F_NBITS-1:0] v_in [ninputs-1:0]  // previous layer's computed outputs
    , input  [`F_NBITS-1:0] tau                 // next random field element from V

    , input  [nmuxsels-1:0] mux_sel             // select bits for mux gates

                                                // Interface for writing evals each round
    , output                f_wren              // write enable for f_j data
    , output                p_wren              // write enable for point data
    , output [`F_NBITS-1:0] fp_data             // f_j or point data

                                                // Interface for post-sumcheck w0 compute
    , input                 comp_w0             // after sumcheck is done, compute w0 for next layer
    , input  [`F_NBITS-1:0] tau_w0              // tau value (from next layer) for computing w0
    , output [`F_NBITS-1:0] w0 [ninbits-1:0]    // evals of gamma(tau) for next layer
    , output                w0_ready_pulse      // computation of w0 is done (pulse)
    , output                w0_ready            // computation of w0 is not currently running

                                                // outputs for ready signaling
    , output                ready_pulse         // pulse when ready
    , output          [1:0] ready_code          // ready code (see above)
    );

// make sure that our parameters are reasonable
generate
    if (ninbits != $clog2(ninputs)) begin: IErr1
        Error_do_not_override_ninbits_in_prover_layer __error__();
    end
    if (nmuxbits != $clog2(nmuxsels)) begin: IErr2
        Error_do_not_override_nmuxins_in_prover_layer __error__();
    end
    if (ngates < 3) begin: IErr3
        Illegal_parameter__ngates_must_be_at_least_3 __error__();
    end
    if (ninputs < 1) begin: IErr4
        Illegal_parameter__ninputs_must_be_at_least_1 __error__();
    end
endgenerate

// ONEM: compute 1-tau
wire en_onem;
wire [`F_NBITS-1:0] m_tau_p1;
wire onem_ready;
field_one_minus ionem
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en_onem)
    , .a            (tau)
    , .ready_pulse  ()
    , .ready        (onem_ready)
    , .c            (m_tau_p1)
    );

// COMPV: compute evaluations of V~
reg en_compv, en_compv_next;
reg restart_compv, restart_compv_next;
reg skip012_reg, skip012_next;
wire compv_ready, compv_ready_pulse;
// intf wires between compute_v and shuf_v
localparam ngates_unshuf = 1 << ($clog2(ninputs) - 1);
wire [`F_NBITS-1:0] v_0_unshuf [ngates_unshuf-1:0];
wire [`F_NBITS-1:0] v_1_unshuf [ngates_unshuf-1:0];
wire [`F_NBITS-1:0] v_tau_unshuf [ngates_unshuf-1:0];
// output from compute_v for reading v(w1) or v(w2)
wire [`F_NBITS-1:0] v_w1w2 = v_0_unshuf[0];
prover_compute_v
   #( .ngates       (ninputs)
    ) icompv
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en_compv)
    , .restart      (restart_compv)
    , .skip012      (skip012_reg)
    , .v_in         (v_in)
    , .tau          (tau)
    , .m_tau_p1     (m_tau_p1)
    , .ready_pulse  (compv_ready_pulse)
    , .ready        (compv_ready)
    , .v_0          (v_0_unshuf)
    , .v_1          (v_1_unshuf)
    , .v_tau        (v_tau_unshuf)
    );

// SHUFV: shuffle COMPV output
wire shufv_ready;
wire [`F_NBITS-1:0] v_0_shuf [ninputs-1:0];
wire [`F_NBITS-1:0] v_1_shuf [ninputs-1:0];
wire [`F_NBITS-1:0] v_tau_shuf [ninputs-1:0];
prover_shuffle_v
   #( .ngates       (ninputs)
    , .plstages     (shuf_plstages)
    ) ishufv
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (compv_ready_pulse & ~skip012_reg)
    , .restart      (restart_compv)
    , .v_0_in       (v_0_unshuf)
    , .v_1_in       (v_1_unshuf)
    , .v_tau_in     (v_tau_unshuf)
    , .ready_pulse  ()
    , .ready        (shufv_ready)
    , .v_0          (v_0_shuf)
    , .v_1          (v_1_shuf)
    , .v_tau        (v_tau_shuf)
    );

// GCOMP[i]: instances of per-gate computations
reg restart_gcomp, restart_gcomp_next;
reg precomp_reg, precomp_next;
wire en_gcomp;
wire [ngates-1:0] gcomp_ready;
wire allcomp_ready = &(gcomp_ready);
wire [`F_NBITS-1:0] gcomp_out [ngates-1:0] [2:0];
// result of evaluating V(w1)
// only valid after we've done half the sumcheck rounds!
reg [`F_NBITS-1:0] v_w1_reg, v_w1_next;
// w2_act is true once we've done half the sumcheck rounds
reg w2_act, w2_next;
// number of bits in gate addresses
localparam ngbits = $clog2(ngates);
localparam nidbits = ngbits + 2*ninbits;
localparam nbidcnt = $clog2(nidbits + 1);
reg [nbidcnt-1:0] bitcnt_reg, bitcnt_next;
genvar GateNum;
generate
    for (GateNum = 0; GateNum < ngates; GateNum = GateNum + 1) begin: GComp
        // figure out this gate's hookups based on layer params
        localparam [`GATEFN_BITS-1:0] gfn = gates_fn[(GateNum*`GATEFN_BITS) +: `GATEFN_BITS];
        localparam [ninbits-1:0] gi0 = gates_in0[(GateNum*ninbits) +: ninbits];
        localparam [ninbits-1:0] gi1 = gates_in1[(GateNum*ninbits) +: ninbits];
        localparam [ngbits-1:0] gid = GateNum;

        // make sure that we claim gmux is at least 1 bit wide
        localparam nb = nmuxbits == 0 ? 1 : nmuxbits;
        localparam [nmuxbits-1:0] gmux = gates_mux[(GateNum*nmuxbits) +: nb];

        if (gi0 >= ninputs || gi1 >= ninputs) begin: IErr5
            Illegal_input_number_declared_for_gate __error__();
        end
        // during the 1st half of the sumcheck (w2_act == 0), vin1
        //   is just the previous layer's evaluation at gi1.
        // during the 2nd half of the sumcheck (w2_act == 1), vin1
        //   is the partial evaluations of v~ for this gate's input 1
        wire [`F_NBITS-1:0] vin1 [2:0];
        assign vin1[0] = w2_act ? v_0_shuf[gi1] : v_in[gi1];
        assign vin1[1] = w2_act ? v_1_shuf[gi1] : v_in[gi1];
        assign vin1[2] = w2_act ? v_tau_shuf[gi1] : v_in[gi1];
        // during the 1st half of the sumcheck (w2_act == 0), vin0
        //   is the partial evaluations of V~ for this gate's input 0
        // during the 2nd half of the sumcheck (w2_act == 1), vin0
        //   is the evaluation of V~_{i+1}(w1).
        wire [`F_NBITS-1:0] vin0 [2:0];
        assign vin0[0] = w2_act ? v_w1_reg : v_0_shuf[gi0];
        assign vin0[1] = w2_act ? v_w1_reg : v_1_shuf[gi0];
        assign vin0[2] = w2_act ? v_w1_reg : v_tau_shuf[gi0];

        // sidestep an issue with Icarus's elaboration process
        wire [`F_NBITS-1:0] this_out [2:0];
        assign gcomp_out[GateNum][0] = this_out[0];
        assign gcomp_out[GateNum][1] = this_out[1];
        assign gcomp_out[GateNum][2] = this_out[2];

        // wire up correct mux_sel bit for this gate
        wire msel = mux_sel[gmux];

        pergate_compute
           #( .gate_fn      (gfn)
            , .nidbits      (nidbits)
            , .id_vec       ({gi1, gi0, gid})
            ) icomp
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (en_gcomp)
            , .restart      (restart_gcomp)
            , .precomp      (precomp_reg)
            , .tau          (tau)
            , .m_tau_p1     (m_tau_p1)
            , .mux_sel      (msel)
            , .vin0         (vin0)
            , .vin1         (vin1)
            , .ready_pulse  ()
            , .ready        (gcomp_ready[GateNum])
            , .gate_out     (this_out)
            );
    end
endgenerate

// FNEG: evaluate field negations of w1 during 1st half of sumcheck
// TODO: in principle we might be able to get away with a single adder
//       for computing this and 1-tau (above). This is only a *very*
//       slight area savings---one adder per layer of the ckt.
wire en_fneg;
wire fneg_ready, fneg_ready_pulse;
wire [`F_NBITS-1:0] nw1_data;
field_negate ifneg
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en_fneg)
    , .a            (tau)
    , .ready_pulse  (fneg_ready_pulse)
    , .ready        (fneg_ready)
    , .c            (nw1_data)
    );

// NW1R: ring buffer for storing evaluations of -w1 during 1st half of sumcheck
// We then repurpose this ring buffer to hold evals of w2-w1 during 2nd half.
wire [`F_NBITS-1:0] nw1_q;
wire [`F_NBITS-1:0] w2_m_w1_q_all [ninbits-1:0];
wire [`F_NBITS-1:0] w2_m_w1_data;
wire [`F_NBITS-1:0] nw1_or_w2mw1_data = w2_act ? w2_m_w1_data : nw1_data;
wire comph_ready_pulse;
wire nw1r_en = comph_ready_pulse | fneg_ready_pulse;
ringbuf_simple
   #( .nbits        (`F_NBITS)
    , .nwords       (ninbits)
    ) inw1r
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (nw1r_en)
    , .wren         (nw1r_en)
    , .d            (nw1_or_w2mw1_data)
    , .q            (nw1_q)
    , .q_all        (w2_m_w1_q_all)
    );

// W1R: ring buffer for storing w1 during 1st half of sumcheck
wire [`F_NBITS-1:0] w1_q_all [ninbits-1:0];
ringbuf_simple
   #( .nbits        (`F_NBITS)
    , .nwords       (ninbits)
    ) iw2r
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (fneg_ready_pulse)
    , .wren         (fneg_ready_pulse)
    , .d            (tau)
    , .q            ()
    , .q_all        (w1_q_all)
    );

// COMPW0: compute evaluations of w0 for next layer at next round
// This uses the values for w1 and w2_m_w1 that we previously stored.
prover_compute_w0
   #( .ninbits      (ninbits)
    ) icompw0
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (comp_w0)
    , .w1           (w1_q_all)
    , .w2_m_w1      (w2_m_w1_q_all)
    , .tau          (tau_w0)
    , .ready_pulse  (w0_ready_pulse)
    , .ready        (w0_ready)
    , .w0           (w0)
    );

// COMPH: build up evaluations of V~(gamma(.)) for the end of the sumcheck
wire en_comph;
reg restart_comph, restart_comph_next;
reg h_rden, h_rden_next;
wire comph_ready;
wire [`F_NBITS-1:0] h_data [ninputs-1:0];
prover_compute_h
   #( .ngates       (ninputs)
    ) icomph
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en_comph)
    , .restart      (restart_comph)
    , .v_in         (v_in)
    , .m_w1         (nw1_q)
    , .w2           (tau)
    , .ready_pulse  (comph_ready_pulse)
    , .ready        (comph_ready)
    , .w2_m_w1      (w2_m_w1_data)
    , .p_rden       (h_rden)
    , .p_out        (h_data)
    );

// ADDT: adder tree
reg en_addt, en_addt_next;
reg [1:0] addin_sel, addin_next;
wire addt_ready_in, addt_ready_out_pulse;
localparam naddgates = (ninputs > ngates) ? ninputs : ngates;
wire [`F_NBITS-1:0] addt_in [naddgates-1:0];
wire [`F_NBITS-1:0] addt_out;
wire addt_out_tag, addt_idle;
// connect output of adder tree to the output ring buffers
assign f_wren = addt_ready_out_pulse & ~addt_out_tag;
reg p_wren_reg, p_wren_next;
assign p_wren = p_wren_reg | (addt_ready_out_pulse & addt_out_tag);
prover_adder_tree_pl
   #( .ngates           (naddgates)
    , .ntagb            (1)
    ) iaddt
    ( .clk              (clk)
    , .rstb             (rstb)
    , .en               (en_addt)
    , .in               (addt_in)
    , .in_tag           (&(addin_sel))      // in_tag == 1 when taking h_data
    , .idle             (addt_idle)
    , .in_ready_pulse   ()
    , .in_ready         (addt_ready_in)
    , .out_ready_pulse  (addt_ready_out_pulse)
    , .out_ready        ()
    , .out              (addt_out)
    , .out_tag          (addt_out_tag)
    );
// connect up adder inputs
generate
    for (GateNum = 0; GateNum < naddgates; GateNum = GateNum + 1) begin: AddHookup
        // mux addt_in based on addin_sel
        wire [`F_NBITS-1:0] g_add_in [3:0];
        assign addt_in[GateNum] = g_add_in[addin_sel];

        // hook up f_j component outputs to g_add_in if possible
        if (GateNum >= ngates) begin: INoHookupFJ
            assign g_add_in[0] = 0;
            assign g_add_in[1] = 0;
            assign g_add_in[2] = 0;
        end else begin: IHookupFJ
            assign g_add_in[0] = gcomp_out[GateNum][0];
            assign g_add_in[1] = gcomp_out[GateNum][1];
            assign g_add_in[2] = gcomp_out[GateNum][2];
        end

        // hook up h_data output to g_add_in if possible
        if (GateNum >= ninputs) begin: INoHookupH
            assign g_add_in[3] = 0;
        end else begin: IHookupH
            assign g_add_in[3] = h_data[GateNum];
        end
    end
endgenerate

// ready indicator to the output state machine
reg ready_reg, ready_next;
reg [1:0] ready_code_reg, ready_code_next;
assign ready_pulse = ready_reg;
assign ready_code = ready_code_reg;

// indicators about where we are in the process
wire precomp_done = bitcnt_reg == ngbits - 1;
wire w1_done = bitcnt_reg == ngbits + ninbits - 1;
wire w2_done = bitcnt_reg == ngbits + 2 * ninbits - 1;
localparam nhpoints = $clog2(ninputs) - 1;   // # points of H(gamma(.)), excluding H(0) and H(1)
wire p_done = bitcnt_reg == nhpoints - 1;
wire f_done = addin_sel == 2'b10;
wire ck_done = bitcnt_reg == nidbits;

// state register
enum { ST_IDLE, ST_ONEM, ST_GCOMP, ST_COMPV, ST_ADDT, ST_H1OUT, ST_ADDT_FIN }
    state_reg, state_next;

// enables for subcomponents above are based on state register
// This is safe because all of these enable signals are edge triggered inside
// the respective blocks.
assign en_onem = state_reg == ST_ONEM;
assign en_fneg = en_onem & ~precomp_reg & ~w2_act;
assign en_comph = en_onem & ~precomp_reg & w2_act;
assign en_gcomp = state_reg == ST_GCOMP;

// fp_data is the circuit output
// most of the time it's the adder tree output, but when we're writing
// H(gamma(0)) and H(gamma(1)) it's not because these come from elsewhere
wire inST_COMPV = state_reg == ST_COMPV;
wire inST_H1OUT = state_reg == ST_H1OUT;
assign fp_data = inST_COMPV ? v_w1_reg : (inST_H1OUT ? v_w1w2 : addt_out);

`ALWAYS_COMB begin
    en_addt_next = 0;
    en_compv_next = 0;
    restart_compv_next = restart_compv;
    restart_gcomp_next = restart_gcomp;
    restart_comph_next = restart_comph;
    skip012_next = skip012_reg;
    precomp_next = precomp_reg;
    v_w1_next = v_w1_reg;
    w2_next = w2_act;
    bitcnt_next = bitcnt_reg;
    h_rden_next = 0;
    addin_next = addin_sel;
    state_next = state_reg;
    ready_code_next = ready_code_reg;
    ready_next = 0;
    p_wren_next = 0;

    case (state_reg)
        // idle state - we begin each round here
        ST_IDLE: begin
            if (en) begin
                if (restart | ck_done) begin
                    // start a new round of the sumcheck protocol
                    restart_compv_next = 1;
                    restart_gcomp_next = 1;
                    restart_comph_next = 1;
                    skip012_next = 0;
                    precomp_next = 1;
                    w2_next = 0;
                    bitcnt_next = 0;
                end else begin
                    // continue sumcheck
                    bitcnt_next = bitcnt_reg + 1;
                end
                state_next = ST_ONEM;
            end
        end

        // compute 1-tau.
        // This state also starts computation of -tau (when we're in the 1st half of sumcheck)
        // or the next evaluations of H(gamma(.)) (when we're in the 2nd half of sumcheck)
        ST_ONEM: begin
            if (onem_ready) begin
                if (precomp_reg & ~precomp_done) begin
                    // if we're just precomputing, go straight to compg
                    state_next = ST_GCOMP;
                end else begin
                    if (precomp_done) begin
                        precomp_next = 0;
                    end
                    
                    // if we've finished one of the phases of the sumcheck,
                    // compute final value V(w1) or V(w2) before continuing
                    if (w1_done || w2_done) begin
                        skip012_next = 1;
                        if (w2_done) begin
                            // next cycle, write H(0) to fp_data ring buffer
                            p_wren_next = 1;
                        end
                    end

                    // once we've kicked off comph the first time, disable its restart bit
                    // (this will happen the cycle after w1_done is asserted)
                    if (w2_act) begin
                        restart_comph_next = 0;
                    end

                    // not precomputing, so we have to compute V before computing gatefns
                    state_next = ST_COMPV;
                    en_compv_next = 1;
                end
            end
        end

        // compute the next values from V
        // Most of the time, this includes both incorporating the new tau value
        // and then computing the next values V(0), V(1), and V(2).
        // However, when skip012 is asserted, we only incorporate the new tau value.
        // This happens twice per sumcheck, once each time we get the last element of w1 or w2.
        ST_COMPV: begin
            if (compv_ready & shufv_ready) begin
                if (skip012_reg) begin
                    // we just skipped 012, so we're finishing w1 or w2
                    if (w1_done) begin
                        skip012_next = 0;           // done with skip012
                        en_compv_next = 1;          // kick off compv again
                        restart_compv_next = 1;     // restarting compv for second half of sumcheck
                        v_w1_next = v_w1w2;  // any register in compv == V(w1)
                        w2_next = 1;                // switch muxes for gcomp inputs
                    end else begin  // finishing w2
                        // We have to wait for the last compute_h evaluation to finish.
                        if (comph_ready) begin
                            // next cycle, write H(1) to fp_data ring buffer
                            state_next = ST_H1OUT;
                            p_wren_next = 1;

                            // done with skip012
                            skip012_next = 0;

                            // send point evals to the adder tree
                            addin_next = 2'b11;
                            bitcnt_next = 0;
                            en_addt_next = 1;
                            h_rden_next = 1;
                        end
                    end
                end else begin
                    restart_compv_next = 0;
                    // ready to compute gate functions
                    state_next = ST_GCOMP;
                end
            end
        end

        // in these two states, we are rippling point evals from comph
        // into the adder tree. Initially we are in ST_H1OUT because
        // that tells the fp_data mux to select v_0_unshuf[0], which
        // is at this point equal to V(w2).
        // Thereafter, we are in ST_ADDT_FIN, in which fp_data is
        // connected to the output of the adder tree.
        ST_ADDT_FIN,
        ST_H1OUT: begin
            state_next = ST_ADDT_FIN;

            if (p_done) begin
                // wait until adder tree has finished processing all inputs we gave it
                if (addt_idle) begin
                    ready_code_next = 2'b10;    // tell the comm link to send the points
                    ready_next = 1;             // (pulse ready)
                    bitcnt_next = nidbits;      // we're done with this round of sumcheck
                    state_next = ST_IDLE;
                end
            end else if (addt_ready_in) begin
                bitcnt_next = bitcnt_reg + 1;
                en_addt_next = 1;
                h_rden_next = 1;
            end
        end

        // For each gate, incorporate the new tau value.
        // When we are not precomputing, compute f_j(0), f_j(1), f_j(2)
        ST_GCOMP: begin
            if (allcomp_ready) begin
                restart_gcomp_next = 0;
                if (precomp_reg) begin
                    // just precomputing
                    ready_code_next = 2'b00;    // tell the comm link to give us another w_0 val
                    ready_next = 1;             // (pulse ready)
                    state_next = ST_IDLE;
                end else begin
                    // compute the values of f_j(0), f_j(1), f_j(2) using adder tree
                    addin_next = 2'b00;
                    en_addt_next = 1;
                    state_next = ST_ADDT;
                end
            end
        end

        // In this state, we ripple f_j evals from gcomp into
        // the adder tree.
        // Once we have rippled in 3 values, wait for the adder tree to be done,
        // and then signal to the comm link that it should send the f_j values.
        ST_ADDT: begin
            if (f_done) begin
                // Wait until adder tree has finished processing all inputs we gave it.
                // Also: don't finish the cycle until comph and fneg both indicate ready
                if (addt_idle & comph_ready & fneg_ready) begin
                    ready_code_next = 2'b01;    // tell the comm link to send the f_j evals
                    ready_next = 1;             // (pulse ready)
                    state_next = ST_IDLE;
                end
            end else if (addt_ready_in) begin
                addin_next = addin_sel + 1;
                en_addt_next = 1;
            end
        end

        // ERROR: unreachable!
        default: begin
            state_next = ST_IDLE;
            bitcnt_next = nidbits;
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_addt <= 0;
        en_compv <= 0;
        restart_compv <= 0;
        restart_gcomp <= 0;
        restart_comph <= 0;
        skip012_reg <= 0;
        precomp_reg <= 0;
        v_w1_reg <= 0;
        w2_act <= 0;
        bitcnt_reg <= nidbits;
        h_rden <= 0;
        addin_sel <= 0;
        state_reg <= ST_IDLE;
        ready_code_reg <= 0;
        ready_reg <= 0;
        p_wren_reg <= 0;
    end else begin
        en_addt <= en_addt_next;
        en_compv <= en_compv_next;
        restart_compv <= restart_compv_next;
        restart_gcomp <= restart_gcomp_next;
        restart_comph <= restart_comph_next;
        skip012_reg <= skip012_next;
        precomp_reg <= precomp_next;
        v_w1_reg <= v_w1_next;
        w2_act <= w2_next;
        bitcnt_reg <= bitcnt_next;
        h_rden <= h_rden_next;
        addin_sel <= addin_next;
        state_reg <= state_next;
        ready_code_reg <= ready_code_next;
        ready_reg <= ready_next;
        p_wren_reg <= p_wren_next;
    end
end

endmodule
`define __module_prover_layer
`endif // __module_prover_layer
