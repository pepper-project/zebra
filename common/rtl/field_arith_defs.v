// definitions for field arithmetic
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

`ifndef __include_field_arith_defs_v

`define USE_P25519

`ifndef USE_P25519
// NOTE -- do not change these without updating util.h with new prime numbers //

`define F_NBITS 61      // number of bits in the field
`define F_Q_P2_MI 1     // for q=2^k-i, this is q + 2 - i (mod q)
`define F_Q_P1_MI 0     // for q=2^k-i, this is q + 1 - i (mod q)
`define F_I 1           // for q=2^k-i, this is i
`define F_M1 61'h1ffffffffffffffe   // -1 mod p
`define F_HALF 61'h1000000000000000 // inverse of 2 mod p

`else

`define F_NBITS 255
`define F_Q_P2_MI 255'h7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffdc
`define F_Q_P1_MI 255'h7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffdb
`define F_I 19
`define F_M1 255'h7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffec
`define F_HALF 255'h3ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7

`endif

//`define USE_FJM1

`define F_ADD_CYCLES 1
`define F_MUL_CYCLES 3

`define __include_field_arith_defs_v
`endif // __include_field_arith_defs_v
