// otp_if.sv
// Stand-in for the foundry OTP IP. top_most's OTP_REQ -> OTP_LATCH protocol
// holds otp_rd_en_o high for exactly one cycle and samples otp_data_i
// combinationally on that same cycle (see otp.sv placeholder comments).
// This BFM reproduces exactly that: no clocked otp.sv instantiated, since
// the real IP is TBD from the foundry.
//
// Word packing: word[i] (i = 0..7) is built from pubkey octets 4*i..4*i+3
// as {octet[4i+3],octet[4i+2],octet[4i+1],octet[4i]} -- same little-endian
// per-word convention used for R_IN/S_IN/DATA_IN.

interface otp_if (input logic clk, input logic rst_n);

  logic [2:0]  otp_addr;
  logic        otp_rd_en;
  logic [31:0] otp_data;

  logic [31:0] pubkey_words [8];

  // Combinational read path -- matches placeholder otp.sv's documented
  // (corrected) protocol.
  always_comb begin
    if (otp_rd_en) otp_data = pubkey_words[otp_addr];
    else           otp_data = 32'h0;
  end

  // Called by the sequence/test to load the pubkey for the vector under
  // test before CTRL.start is written.
  // Same convention as R_IN/S_IN/DATA_IN (see csr_seq_lib.sv pack_word):
  // first octet of each chunk goes in the word's most-significant byte.
  function automatic void load_pubkey(input byte unsigned pk[32]);
    for (int i = 0; i < 8; i++) begin
      pubkey_words[i] = {pk[4*i], pk[4*i+1], pk[4*i+2], pk[4*i+3]};
    end
  endfunction

endinterface : otp_if