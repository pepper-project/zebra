// synthesis VERILOG_INPUT_VERSION SYSTEMVERILOG_2009
// compute gate's total contribution to sumcheck outputs and wiring predicate
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

// This module replaces compute_addmul and compute_fj, using a single
// multiplier for all functionality therein.

`ifndef __module_pergate_compute_am_fj
`include "simulator.v"
`include "field_arith_defs.v"
`include "field_multiplier.sv"
module pergate_compute_am_fj
    ( input                 clk
    , input                 rstb

    , input                 en_am
    , input                 restart
    , input                 gate_id_bit

    , input  [`F_NBITS-1:0] tau
    , input  [`F_NBITS-1:0] m_tau_p1

    , output                ready_pulse_am
    , output                ready_am
    , output [`F_NBITS-1:0] addmul_eval

    , input                 en_fj
    , input  [`F_NBITS-1:0] gatefn [2:0]
    , input  [`F_NBITS-1:0] addmul [2:0]

    , output                ready_fj
    , output [`F_NBITS-1:0] fj [2:0]
    );

// controls for the shared field multiplier
reg [`F_NBITS-1:0] mul_a, mul_b;
reg en_mul, en_mul_next;
wire [`F_NBITS-1:0] mul_c;
wire mul_ready;
field_multiplier imul
    ( .clk          (clk)
    , .rstb         (rstb)
    , .en           (en_mul)
    , .a            (mul_a)
    , .b            (mul_b)
    , .ready_pulse  ()
    , .ready        (mul_ready)
    , .c            (mul_c)
    );

// state machine
enum { ST_IDLE, ST_AM, ST_AMRST, ST_AMRDY, ST_FJ0, ST_FJ1, ST_FJ2 } state_reg, state_next;
wire inST_IDLE = state_reg == ST_IDLE;
wire inST_AM = state_reg == ST_AM;
wire inST_AMRST = state_reg == ST_AMRST;
wire inST_AMRDY = state_reg == ST_AMRDY;
wire inST_FJ0 = state_reg == ST_FJ0;
wire inST_FJ1 = state_reg == ST_FJ1;
wire inST_FJ2 = state_reg == ST_FJ2;

assign ready_pulse_am = inST_AMRDY;
assign ready_am = ~((inST_IDLE & en_am) | inST_AM | inST_AMRST);
assign ready_fj = ~((inST_IDLE & en_fj) | inST_FJ0 | inST_FJ1 | inST_FJ2);

reg [`F_NBITS-1:0] fj_reg [1:0];
reg [`F_NBITS-1:0] fj_next [1:0];
assign fj[0] = fj_reg[0];
assign fj[1] = fj_reg[1];
assign fj[2] = mul_c;

reg [`F_NBITS-1:0] am_reg, am_next;
assign addmul_eval = am_reg;
reg id_reg, id_next;

`ALWAYS_COMB begin
    en_mul_next = 0;
    fj_next[0] = fj_reg[0];
    fj_next[1] = fj_reg[1];
    am_next = am_reg;
    state_next = state_reg;
    mul_a = {(`F_NBITS){1'bX}};
    mul_b = {(`F_NBITS){1'bX}};
    id_next = id_reg;

    case (state_reg)
        ST_IDLE: begin
            if (en_am) begin
                id_next = gate_id_bit;
                en_mul_next = 1;
                if (restart) begin
                    state_next = ST_AMRST;
                end else begin
                    state_next = ST_AM;
                end
            end else if (en_fj) begin
                en_mul_next = 1;
                state_next = ST_FJ0;
            end
        end

        ST_AM: begin
            mul_a = am_reg;
            mul_b = id_reg ? tau : m_tau_p1;
            if (mul_ready) begin
                am_next = mul_c;
                state_next = ST_AMRDY;
            end
        end

        ST_AMRST: begin
            mul_a = 1;
            mul_b = id_reg ? tau : m_tau_p1;
            if (mul_ready) begin
                am_next = mul_c;
                state_next = ST_AMRDY;
            end
        end

        ST_AMRDY: begin
            state_next = ST_IDLE;
        end

        ST_FJ0: begin
            mul_a = gatefn[0];
            mul_b = addmul[0];
            if (mul_ready) begin
                fj_next[0] = mul_c;
                en_mul_next = 1;
                state_next = ST_FJ1;
            end
        end

        ST_FJ1: begin
            mul_a = gatefn[1];
            mul_b = addmul[1];
            if (mul_ready) begin
                fj_next[1] = mul_c;
                en_mul_next = 1;
                state_next = ST_FJ2;
            end
        end

        ST_FJ2: begin
            mul_a = gatefn[2];
            mul_b = addmul[2];
            if (mul_ready) begin
                state_next = ST_IDLE;
            end
        end

        default: begin
            state_next = ST_IDLE;
        end
    endcase
end

`ALWAYS_FF @(posedge clk or negedge rstb) begin
    if (~rstb) begin
        en_mul <= 0;
        fj_reg[0] <= 0;
        fj_reg[1] <= 0;
        am_reg <= 0;
        state_reg <= ST_IDLE;
        id_reg <= 0;
    end else begin
        en_mul <= en_mul_next;
        fj_reg[0] <= fj_next[0];
        fj_reg[1] <= fj_next[1];
        am_reg <= am_next;
        state_reg <= state_next;
        id_reg <= id_next;
    end
end

endmodule
`define __module_pergate_compute_am_fj
`endif // __module_compute_am_fj
