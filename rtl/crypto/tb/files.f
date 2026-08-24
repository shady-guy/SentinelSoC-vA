-sv
-timescale 1ns/1ps

// ---- DUT sources (root = rtl/crypto) ----
../SHA/sha512_pkg.sv
../ALU/pseudo_mersenne.sv
../ALU/multiplier.sv
../ALU/alu.sv
../ALU/alu_top.sv
../SHA/sha512_msg_sched.sv
../SHA/sha512_preprocessor.sv
../SHA/sha512_round.sv
../SHA/sha512_top.sv
../ed/reg_file.sv
../ed/micro_seq.sv
../ed/master_fsm.sv
../ed/top_ed25519.sv
../top_most.sv

// NOTE: rtl/crypto/otp.sv and rtl/crypto/tb_top_most_firmware.sv are
// deliberately NOT compiled here. otp.sv is the foundry placeholder
// (this TB drives otp_data_i itself via otp_if.sv). tb_top_most_firmware.sv
// is your older TB, superseded by tb_top.sv below.

// ---- TB sources (this directory) ----
rfc8032_vectors_pkg.sv
csr_if.sv
otp_if.sv
probe_if.sv
tb_pkg.sv
tb_top.sv
