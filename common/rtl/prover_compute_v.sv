// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// compute new values of V(.) for each round of the sumcheck
//   (gate labels are replaced in LSB->MSB order)
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// Wire together and synchronize prover_compute_v_elems for each value in the
// inputs to a given layer of the circuit.
//
// This has two steps:
//
// 1. Compute new values of V(tau) given random element from previous round
//    of sumcheck. On the first round of the sumcheck (i.e., when restart
//    is asserted), instead just load values from v_in.
//
//    In the non-restart case, we do this in 3 steps:
//
//    a. Compute 1-tau from tau
//    b. Multiply by tau or 1-tau and add the results
//    c. Save the resulting values in the v registers.
//
//    In the restart case, we simply load v_in into the v registers.
//
// 2. Compute values of V(0), V(1), and V(2) given the new v register values.
//
// Step 1(c) has a slight subtlety depending on whether the gate labels
// are replaced with random elements from LSB->MSB or MSB->LSB. This
// module assumes LSB->MSB! See below for more info on the other direction.
//
// ## V Update and Label Replacement Order ##
//
// To start, we have (say) 8 evaluations of V, e.g., V(0, 0, 0) = v000.
// Computing V(x,y,{0,1}) is trivial---it is just a matter of selecting the
// correct value from the existing evaluations.
//
// Computing V(x,x,2) is only slightly harder. Recall that we can write
//
// V(x2, x1, x0) :=
//     (1-x2)*(1-x1)*(1-x0) * v000 +
//     (1-x2)*(1-x1)*(  x0) * v001 +
//     (1-x2)*(  x1)*(1-x0) * v010 +
//     (1-x2)*(  x1)*(  x0) * v011 +
//     (  x2)*(1-x1)*(1-x0) * v100 +
//     (  x2)*(1-x1)*(  x0) * v101 +
//     (  x2)*(  x1)*(1-x0) * v110 +
//     (  x2)*(  x1)*(  x0) * v111 ;
//
// To compute V(0, 0, 2), we note that the only summands that are nonzero in
// this case are the v000 and v001 terms. Thus, we can write
//   V(0, 0, 2) := (1-2) * v000 + 2 * v001;
// A similar argument applies to V(0, 0, tau), for a random value tau given
// by the Verifier.
//
// In the next round of the sumcheck protocol, we can write
//
// V(x2, x1, tau) :=
//     (1-x2)*(1-x1)*(1-tau) * v000 +
//     (1-x2)*(1-x1)*(  tau) * v001 +
//     (1-x2)*(  x1)*(1-tau) * v010 +
//     (1-x2)*(  x1)*(  tau) * v011 +
//     (  x2)*(1-x1)*(1-tau) * v100 +
//     (  x2)*(1-x1)*(  tau) * v101 +
//     (  x2)*(  x1)*(1-tau) * v110 +
//     (  x2)*(  x1)*(  tau) * v111 ;
//
// But it's clear from the expression for V(0, 0, 2) above that we can
// reduce this to:
//
// V(x2, x1, tau) :=
//     (1-x2)*(1-x1) * V(0, 0, tau) +
//     (1-x2)*(  x1) * V(0, 1, tau) +
//     (  x2)*(1-x1) * V(1, 0, tau) +
//     (  x2)*(  x1) * V(1, 1, tau) ;
//
// Now we have
//   V(0, 2, tau) = (1-2) * V(0, 0, tau) + 2 * V(0, 1, tau);
//
// In other words, during the first round, we want v000 and v001 to be inputs
// to a compute_v_elem instance; and after the second round, we want
// V(0, 0, tau) and V(0, 1, tau) to be those inputs. This continues: in the
// next round, that compute_v_elem instance should see V(0, tau1, tau0) and
// V(1, tau1, tau0).
//
// Assuming that compute_v_elem instances are fed by registers v_reg[..],
// arranging for those registers to be correctly updated after each
// evaluation involves storing the V(x, tau) evaluations in the proper
// v_reg[] address.
//
// For LSB->MSB order:
//   - the ith compute_v_elem instance takes as inputs v_reg[i] and v_reg[i + 1]
//   - the ith compute_v_elem instance's V(tau) output should be stored in
//     v_reg[i] and v_reg[i + ngates_out], ngates_out = 2^($clog(ngates)-1)
//
// ## Shuffling ##
//
// After each step of reduction as above, the new values must be routed to
// their destination gates as appropriate. Sadly, this requires a shuffling
// step, as evidence in the example below:
//
// V000 \
// V001 - V00x \
// V010 \        V0xx
// V011 - V01x /      \
// V100 \               Vxxx
// V101 - V10x \      /
// V110 \        V1xx
// V111 - V11x /
//
// In the first step, V000 to V111 are stored in v_reg[0] to v_reg[7].
//
// At the second step, V00x to V11x are stored in v_reg[0] to v_reg[3]
// (and repeated in v_reg[4] to v_reg[7]).
//
// At the third step, V0xx and V1xx are stored in v_reg[0] and v_reg[1]
// (and repeated in the rest of the registers).
//
// Now, note that a gates whose inputs in the circuit are V010 and V011
// both want the V01x value after the second step; but in the third step,
// they want V0xx. So this means that these gates want v_reg[1] after step
// 2, but v_reg[0] after step 3. In other words, the circuit should output
//
// V00x  and then   V0xx
// V00x             V0xx
// V01x             V0xx
// V01x             V0xx
// V10x             V1xx
// V10x             V1xx
// V11x             V1xx
// V11x             V1xx
//
// but storing values in this order in v_reg[..] is at odds with the
// requirements given in the previous section.
//
// So we conclude that either the inputs to the compute_v_elem insts must
// be shuffled, or the outputs from this circuit must be shuffled. For
// the sake of simplicity, we partition the compute and shuffle functions
// into two separate circuits, i.e., we choose the second option.

`ifndef __module_prover_compute_v
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_multiplier.sv"
`include "prover_compute_v_elem.sv"
module prover_compute_v
   #( parameter ngates = 8
// NOTE do not override parameters below this line //
    , parameter ngates_out = 1 << ($clog2(ngates) - 1)
   )( input                 clk
    , input                 rstb

    , input                 en
    , input                 restart
    , input                 skip012

    , input  [`F_NBITS-1:0] v_in [ngates-1:0]
    , input  [`F_NBITS-1:0] tau
    , input  [`F_NBITS-1:0] m_tau_p1

    , output                ready_pulse
    , output                ready
    , output [`F_NBITS-1:0] v_0 [ngates_out-1:0]
    , output [`F_NBITS-1:0] v_1 [ngates_out-1:0]
    , output [`F_NBITS-1:0] v_tau [ngates_out-1:0]
    );

// make sure that parameters have not been overridden
generate
    if (ngates_out != 1 << ($clog2(ngates) - 1)) begin: IErr1
        Error_do_not_override_ngates_out_in_prover_compute_v __error__();
    end
endgenerate

// how many ready bits do we need in total
localparam nrdy = (ngates / 2) + (ngates % 2);
integer GateNumC, GateNumF;

// state machine
enum { ST_IDLE, ST_UPDATE, ST_FINISH } state_reg, state_next;
wire inST_FINISH = state_reg == ST_FINISH;
wire inST_IDLE = state_reg == ST_IDLE;

// select tau value (either supplied value or 2)
// depending which part of the computation we're in
`ifndef USE_FJM1
    wire [`F_NBITS-1:0] tau_finish = {{(`F_NBITS-2){1'b0}},2'b10};
    wire [`F_NBITS-1:0] mtau_finish = `F_M1;
`else
    wire [`F_NBITS-1:0] tau_finish = `F_M1;
    wire [`F_NBITS-1:0] mtau_finish = {{(`F_NBITS-2){1'b0}},2'b10};
`endif

wire [`F_NBITS-1:0] tau_sel = inST_FINISH ? tau_finish : tau;
wire [`F_NBITS-1:0] m_tau_p1_sel = inST_FINISH ? mtau_finish : m_tau_p1;

// working copies of V
reg [`F_NBITS-1:0] v_reg [ngates-1:0], v_next [ngates-1:0];
// other hookups for v_elems
wire [nrdy-1:0] velem_rdy;
wire all_velem_rdy = &velem_rdy;
reg en_velem, en_velem_next;

// ready signal
reg en_dly;
wire start = en & ~en_dly;
assign ready = inST_IDLE & ~start;
reg ready_dly;
assign ready_pulse = ready & ~ready_dly;

// do hookup and generation of elements
genvar GateNum;
generate
    // hook up v0 and v1 outputs
    for (GateNum = 0; GateNum < ngates_out; GateNum = GateNum + 1) begin: VHookup
        if (GateNum * 2 < ngates) begin: VHookupEven
            assign v_0[GateNum] = v_reg[GateNum * 2];
        end else begin: VNoHookupEven
            assign v_0[GateNum] = 0;
        end

        if (GateNum * 2 + 1 < ngates) begin: VHookupOdd
            assign v_1[GateNum] = v_reg[GateNum * 2 + 1];
        end else begin: VNoHookupOdd
            assign v_1[GateNum] = 0;
        end
    end

    // create vtau outputs for each pair of inputs
    for (GateNum = 0; GateNum < ngates / 2; GateNum = GateNum + 1) begin: VElem
        prover_compute_v_elem ivelem
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (en_velem)
            , .v0           (v_reg[GateNum * 2])
            , .v1           (v_reg[GateNum * 2 + 1])
            , .tau          (tau_sel)
            , .m_tau_p1     (m_tau_p1_sel)
            , .ready_pulse  ()
            , .ready        (velem_rdy[GateNum])
            , .vtau         (v_tau[GateNum])
            );
    end

    // if we have a lone input, it must have an even-numbered
    // label, so we can just multiply by 1-tau.
    if (ngates % 2 == 1) begin: VSingle
        field_multiplier imult
            ( .clk          (clk)
            , .rstb         (rstb)
            , .en           (en_velem)
            , .a            (m_tau_p1_sel)
            , .b            (v_reg[ngates-1])
            , .ready_pulse  ()
            , .ready        (velem_rdy[ngates/2])
            , .c            (v_tau[ngates/2])
            );
    end

    // tie any extraneous v_tau outputs to 0
    for (GateNum = nrdy; GateNum < ngates_out; GateNum = GateNum + 1) begin: VDfl
        assign v_tau[GateNum] = 0;
    end
endgenerate

`ALWAYS_COMB begin
    state_next = state_reg;
    en_velem_next = 0;
    for (GateNumC = 0; GateNumC < ngates; GateNumC = GateNumC + 1) begin
        v_next[GateNumC] = v_reg[GateNumC];
    end

    case (state_reg)
        // wait for an enable signal and dispatch
        ST_IDLE: begin
            if (start) begin
                en_velem_next = 1;
                if (restart) begin
                    // restarting --- just load evaluations from v_in
                    for (GateNumC = 0; GateNumC < ngates; GateNumC = GateNumC + 1) begin
                        v_next[GateNumC] = v_in[GateNumC];
                    end

                    // and compute V(0), V(1), and V(2)
                    state_next = ST_FINISH;
                end else begin
                    // continuing --- first, we have to compute new V from tau
                    state_next = ST_UPDATE;
                end
            end
        end

        ST_UPDATE: begin
            // wait until ivelems have computed new values for V
            if (all_velem_rdy) begin
                // now update the values in v_regs
                for (GateNumC = 0; GateNumC < ngates_out; GateNumC = GateNumC + 1) begin
                    v_next[GateNumC] = v_tau[GateNumC];
                    if (GateNumC + ngates_out < ngates) begin
                        v_next[GateNumC + ngates_out] = v_tau[GateNumC];
                    end
                end

                if (~skip012) begin
                    // now compute V(0), V(1), and V(2)
                    en_velem_next = 1;
                    state_next = ST_FINISH;
                end else begin
                    // skipping V(0), V(1), and V(2)
                    // we do this when we receive the last element of w1 or w2 from V
                    // (the result in this case is v1 or v2)
                    state_next = ST_IDLE;
                end
            end
        end

        ST_FINISH: begin
            if (all_velem_rdy) begin
                state_next = ST_IDLE;
            end
        end

        default: begin
            // unreachable
            state_next = ST_IDLE;
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        ready_dly <= 1;
        state_reg <= ST_IDLE;
        en_dly <= 1;
        en_velem <= 0;
        for (GateNumF = 0; GateNumF < ngates; GateNumF = GateNumF + 1) begin
            v_reg[GateNumF] <= 0;
        end
    end else begin
        ready_dly <= ready;
        state_reg <= state_next;
        en_dly <= en;
        en_velem <= en_velem_next;
        for (GateNumF = 0; GateNumF < ngates; GateNumF = GateNumF + 1) begin
            v_reg[GateNumF] <= v_next[GateNumF];
        end
    end
end

endmodule
`define __module_prover_compute_v
`endif // __module_prover_compute_v
