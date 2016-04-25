// definitions for communicating with the verifier

`ifndef __include_verifier_interface_defs_v

//data the prover requests: first three arguments are always id,
//`CMT_*, <vec of registers to read or write to>.
`define CMT_INPUT 10000 // cmt_request(.., howMany),       
`define CMT_Q0 20000    // cmt_request(.., howMany),       
`define CMT_R 30000     // cmt_request(.., layer, round)   
`define CMT_TAU 40000   // cmt_request(.., layer)          
`define CMT_QI 50000    // cmt_request(.., layer, howMany) 
`define CMT_MUXSEL 55000// cmt_request(.., howMany)
//data the prover sends. first three arguments are always id, `CMT_*, (data to send).
`define CMT_OUTPUT 60000 // cmt_send(.., howMany) 
`define CMT_F012 70000   // cmt_send(.., layer, round) 
`define CMT_H  90000     // cmt_send(.., layer, howMany);

`define __include_verifier_interface_defs_v
`endif // __include_verifier_interface_defs_v
