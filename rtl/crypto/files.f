-sv
-timescale 1ns/1ps

// ---- DUT (as given) ----
SHA/sha512_pkg.sv
ALU/pseudo_mersenne.sv
ALU/multiplier.sv
ALU/alu.sv
ALU/alu_top.sv
SHA/sha512_msg_sched.sv
SHA/sha512_padder.sv
SHA/sha512_round.sv
SHA/sha512_top.sv
ed/reg_file.sv
ed/micro_seq.sv
ed/master_fsm.sv
ed/top_ed25519.sv
otp.sv
top_most.sv
// NOTE: tb_top_most_firmware.sv (your old firmware-driven TB)
// intentionally dropped -- it is replaced by the UVM env below.

// ---- UVM TB (order matters: interfaces/pkg before tb_pkg, tb_pkg before tb_top) ----
tb/rfc8032_vectors_pkg.sv
tb/csr_if.sv
tb/otp_if.sv
tb/probe_if.sv
tb/tb_pkg.sv
tb/tb_top.sv
