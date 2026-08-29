// csr_seq_lib.sv
// CSR address map (from top_most.sv)
`define CTRL_OFF   32'h000
`define STATUS_OFF 32'h004
`define MSGLEN_OFF 32'h008
`define RIN_OFF    32'h00C
`define SIN_OFF    32'h010
`define DATAIN_OFF 32'h014

//=====================================================================
// Base sequence: reusable CSR bus tasks
//=====================================================================
class csr_base_seq extends uvm_sequence #(csr_seq_item);

  `uvm_object_utils(csr_base_seq)

  virtual otp_if otp_vif;

  function new(string name = "csr_base_seq");
    super.new(name);
  endfunction

  task pre_body();
    if (!uvm_config_db#(virtual otp_if)::get(null, "*", "otp_vif", otp_vif))
      `uvm_fatal("CSR_SEQ", "virtual otp_if not set in config_db")
  endtask

  task write_reg(bit [31:0] addr, bit [31:0] data);
    csr_seq_item item = csr_seq_item::type_id::create("wr_item");
    start_item(item);
    void'(item.randomize() with { kind == csr_seq_item::CSR_WRITE;
                                   local::addr == addr;
                                   wdata       == data; });
    finish_item(item);
  endtask

  task read_reg(bit [31:0] addr, output bit [31:0] data);
    csr_seq_item item = csr_seq_item::type_id::create("rd_item");
    start_item(item);
    void'(item.randomize() with { kind == csr_seq_item::CSR_READ;
                                   local::addr == addr; });
    finish_item(item);
    data = item.rdata;
  endtask

  task pulse_start_verify();
    csr_seq_item item = csr_seq_item::type_id::create("sv_item");
    start_item(item);
    void'(item.randomize() with { kind == csr_seq_item::START_VERIFY_PULSE; });
    finish_item(item);
  endtask

  // Poll STATUS until ready_for_word (bit1) is set.
  task wait_ready_for_word();
    bit [31:0] status;
    do begin
      read_reg(`STATUS_OFF, status);
    end while (!status[1]);
  endtask

  // Poll STATUS until done (bit2) is set. Returns signature_valid (bit3).
  task wait_done(output bit sig_valid);
    bit [31:0] status;
    do begin
      read_reg(`STATUS_OFF, status);
    end while (!status[2]);
    sig_valid = status[3];
  endtask

  // Poll STATUS until busy (bit0) clears -- used after abort/soft-reset.
  task wait_idle();
    bit [31:0] status;
    do begin
      read_reg(`STATUS_OFF, status);
    end while (status[0]);
  endtask

  // NOTE: this was flipped from an earlier version. top_most's R_IN/S_IN/
  // DATA_IN capture applies one byte-swap, and sha512_msg_sched applies a
  // second byte-swap on its own capture -- the two cancel out exactly, so
  // whatever byte order is written on the CSR bus lands UNCHANGED in the
  // SHA message schedule. For that to be correct SHA-512 input (and for
  // r_reg/s_reg/pubkey_reg to land as the correct little-endian 256-bit
  // integers the Ed25519 ALU expects), the first octet of each 4-byte
  // chunk must be the CSR word's most-significant byte.
  function bit [31:0] pack_word(byte unsigned b[], int base_idx);
    return {b[base_idx], b[base_idx+1], b[base_idx+2], b[base_idx+3]};
  endfunction

endclass : csr_base_seq

//=====================================================================
// RFC 8032 KAT sequence: drives one full boot-verify transaction for a
// given ed25519_vector_t. Firmware write order: R_IN x8, S_IN x8,
// MSG_LEN, CTRL.start, then poll+DATA_IN per message word.
//=====================================================================
class rfc8032_kat_seq extends csr_base_seq;

  `uvm_object_utils(rfc8032_kat_seq)

  rfc8032_vectors_pkg::ed25519_vector_t vec;
  bit observed_sig_valid;

  function new(string name = "rfc8032_kat_seq");
    super.new(name);
  endfunction

  task body();
    int unsigned n_words;
    int unsigned msg_len_words;

    // top_most's FSM has no self-transition out of ST_DONE -- it stays
    // there until CTRL.abort/CTRL.softrst forces it back to ST_IDLE.
    // Force a clean IDLE state before every KAT run, otherwise a second
    // (or later) test in the same sim silently no-ops: CTRL.start is
    // only honored from ST_IDLE, so without this the DUT just keeps
    // reporting the PREVIOUS test's stale signature_valid_o.
    write_reg(`CTRL_OFF, 32'h4); // soft-reset
    wait_idle();

    // OTP must be loaded before the DUT reaches ST_OTP_REQ.
    otp_vif.load_pubkey(vec.pubkey_bytes);

    // R_IN x8 (words 0..7, first write = octets 0..3)
    for (int i = 0; i < 8; i++)
      write_reg(`RIN_OFF, pack_word(vec.r_bytes, 4*i));

    // S_IN x8
    for (int i = 0; i < 8; i++)
      write_reg(`SIN_OFF, pack_word(vec.s_bytes, 4*i));

    // MSG_LEN in 32-bit WORDS = R(8w) + A(8w) + message words
    msg_len_words = vec.msg_len_bytes / 4;
    n_words       = 16 + msg_len_words;
    write_reg(`MSGLEN_OFF, n_words);

    // Hand the expected outcome to the scoreboard (which independently
    // checks the verify_done_o/signature_valid_o pins) before kicking off.
    test_oracle::push(vec.expect_pass);

    // Kick off. start_verify_i latches independently and is only
    // consumed once the FSM reaches ST_WAIT_START (after LOAD_REGS),
    // so it is safe to pulse it here.
    write_reg(`CTRL_OFF, 32'h1);       // CTRL.start
    pulse_start_verify();

    // Stream the message body, one word per DATA_IN handshake.
    for (int i = 0; i < msg_len_words; i++) begin
      wait_ready_for_word();
      write_reg(`DATAIN_OFF, pack_word(vec.msg_bytes, 4*i));
    end

    wait_done(observed_sig_valid);

    if (observed_sig_valid != vec.expect_pass)
      `uvm_error("RFC8032_SEQ",
        $sformatf("%s: expected signature_valid=%0b, STATUS reported %0b",
                   vec.name, vec.expect_pass, observed_sig_valid))
    else
      `uvm_info("RFC8032_SEQ",
        $sformatf("%s: STATUS signature_valid=%0b matches expected",
                   vec.name, observed_sig_valid), UVM_LOW)
  endtask

endclass : rfc8032_kat_seq

//=====================================================================
// Abort / soft-reset sequence: starts a transaction using TEST1 vector,
// then asserts CTRL.abort (or CTRL.softrst) partway through R_IN feed,
// and checks the FSM returns to IDLE (busy deasserts).
//=====================================================================
class abort_seq extends csr_base_seq;

  `uvm_object_utils(abort_seq)

  bit use_softrst; // 0 = abort bit, 1 = soft_reset bit

  function new(string name = "abort_seq");
    super.new(name);
  endfunction

  task body();
    rfc8032_vectors_pkg::ed25519_vector_t vec;
    bit [31:0] status;
    vec = rfc8032_vectors_pkg::get_test1();

    otp_vif.load_pubkey(vec.pubkey_bytes);

    for (int i = 0; i < 8; i++)
      write_reg(`RIN_OFF, pack_word(vec.r_bytes, 4*i));
    for (int i = 0; i < 8; i++)
      write_reg(`SIN_OFF, pack_word(vec.s_bytes, 4*i));
    write_reg(`MSGLEN_OFF, 32'd16);
    write_reg(`CTRL_OFF, 32'h1); // start

    // Let it run a few cycles into the boot sequence, then abort/soft-reset.
    // Clock period is fixed at 10ns (confirmed) -- 5 cycles = 50ns.
    #50ns;

    write_reg(`CTRL_OFF, use_softrst ? 32'h4 : 32'h2);

    wait_idle();
    read_reg(`STATUS_OFF, status);
    if (status[0] !== 1'b0)
      `uvm_error("ABORT_SEQ", "busy bit did not clear after abort/soft-reset")
    else
      `uvm_info("ABORT_SEQ",
        $sformatf("%s returned FSM to IDLE as expected",
                   use_softrst ? "soft-reset" : "abort"), UVM_LOW)
  endtask

endclass : abort_seq

//=====================================================================
// Top virtual sequence: runs all scenarios back to back on one agent.
//=====================================================================
class top_virtual_seq extends uvm_sequence #(csr_seq_item);

  `uvm_object_utils(top_virtual_seq)
  `uvm_declare_p_sequencer(csr_sequencer)

  virtual reset_if rst_vif;

  function new(string name = "top_virtual_seq");
    super.new(name);
  endfunction

  task pre_body();
    if (!uvm_config_db#(virtual reset_if)::get(null, "*", "rst_vif", rst_vif))
      `uvm_fatal("TOP_VSEQ", "virtual reset_if not set in config_db")
  endtask

  task body();
    rfc8032_kat_seq kat;
    abort_seq       ab;

    // top_most is a boot-time-only design (verifies once per reset cycle,
    // per its own "no retry semantics needed" comment) -- reset before
    // every scenario so no state survives from the previous one.

    // 1) TEST 1 -- expect verified
    rst_vif.do_reset();
    kat = rfc8032_kat_seq::type_id::create("kat_test1");
    kat.vec = rfc8032_vectors_pkg::get_test1();
    kat.start(p_sequencer);

    // 2) TEST 1 with corrupted S -- expect unverified
    rst_vif.do_reset();
    kat = rfc8032_kat_seq::type_id::create("kat_test1_bad");
    kat.vec = rfc8032_vectors_pkg::get_test1_bad_sig();
    kat.start(p_sequencer);

    // 3) TEST SHA(abc) -- expect verified, exercises multi-block SHA path
    rst_vif.do_reset();
    kat = rfc8032_kat_seq::type_id::create("kat_test_sha_abc");
    kat.vec = rfc8032_vectors_pkg::get_test_sha_abc();
    kat.start(p_sequencer);

    // 4) mid-operation abort
    rst_vif.do_reset();
    ab = abort_seq::type_id::create("abort_case");
    ab.use_softrst = 1'b0;
    ab.start(p_sequencer);

    // 5) mid-operation soft-reset
    rst_vif.do_reset();
    ab = abort_seq::type_id::create("softrst_case");
    ab.use_softrst = 1'b1;
    ab.start(p_sequencer);
  endtask

endclass : top_virtual_seq