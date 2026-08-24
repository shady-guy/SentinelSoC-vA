// tb_top.sv
`timescale 1ns / 1ps

module tb_top;

  import uvm_pkg::*;
  import tb_pkg::*;

  //---------------------------------------------------------------
  // Clock / reset : 10ns period (100MHz), confirmed
  //---------------------------------------------------------------
  logic clk;
  logic rst_n;

  initial clk = 1'b0;
  always #5ns clk = ~clk;

  initial begin
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  //---------------------------------------------------------------
  // Interfaces
  //---------------------------------------------------------------
  csr_if   u_csr_if (.clk(clk), .rst_n(rst_n));
  otp_if   u_otp_if (.clk(clk), .rst_n(rst_n));
  probe_if u_probe_if (.clk(clk));

  //---------------------------------------------------------------
  // DUT
  //---------------------------------------------------------------
  top_most dut (
    .clk               (clk),
    .rst_n             (rst_n),

    .csr_req_i         (u_csr_if.csr_req),
    .csr_we_i          (u_csr_if.csr_we),
    .csr_be_i          (u_csr_if.csr_be),
    .csr_addr_i        (u_csr_if.csr_addr),
    .csr_wdata_i       (u_csr_if.csr_wdata),
    .csr_gnt_o         (u_csr_if.csr_gnt),
    .csr_rvalid_o      (u_csr_if.csr_rvalid),
    .csr_rdata_o       (u_csr_if.csr_rdata),
    .csr_err_o         (u_csr_if.csr_err),

    .start_verify_i    (u_csr_if.start_verify),
    .otp_addr_o        (u_otp_if.otp_addr),
    .otp_rd_en_o       (u_otp_if.otp_rd_en),
    .otp_data_i        (u_otp_if.otp_data),
    .boot_active_o     (u_csr_if.boot_active),
    .verify_done_o     (u_csr_if.verify_done),
    .signature_valid_o (u_csr_if.signature_valid)
  );

  // Coverage-only hierarchical tap into the DUT's internal FSM state
  // (not a port -- top_most does not expose it).
  assign u_probe_if.fsm_state = dut.state;

  //---------------------------------------------------------------
  // DEBUG ONLY -- dumps internal captured registers so you can diff
  // them against known-good RFC 8032 values by hand. Remove once the
  // TEST1 mismatch is root-caused.
  //---------------------------------------------------------------
  always @(dut.state) begin
    if (dut.state == dut.ST_WAIT_INTR)
      $display("[DBG %0t] entering ST_WAIT_INTR: r_reg=%h s_reg=%h pubkey_reg=%h sha_len_reg=%0d sha_fed=%0d",
                $time, dut.r_reg, dut.s_reg, dut.pubkey_reg, dut.sha_len_reg, dut.sha_fed);
    if (dut.state == dut.ST_LOAD_REGS)
      $display("[DBG %0t] entering ST_LOAD_REGS: hash_reg=%h", $time, dut.hash_reg);
    if (dut.state == dut.ST_DONE)
      $display("[DBG %0t] ST_DONE: signature_valid_o=%b", $time, u_csr_if.signature_valid);
  end

  //---------------------------------------------------------------
  // UVM hookup
  //---------------------------------------------------------------
  initial begin
    uvm_config_db#(virtual csr_if.DRIVER)::set(null, "uvm_test_top.env.agent.driver",  "vif", u_csr_if);
    uvm_config_db#(virtual csr_if.MONITOR)::set(null, "uvm_test_top.env.agent.monitor", "vif", u_csr_if);
    uvm_config_db#(virtual otp_if)::set(null, "*", "otp_vif", u_otp_if);
    uvm_config_db#(virtual probe_if)::set(null, "uvm_test_top.env.coverage", "pvif", u_probe_if);

    run_test("tb_test");
  end

  //---------------------------------------------------------------
  // Optional waveform dump
  //---------------------------------------------------------------
  initial begin
    if ($test$plusargs("DUMP_WAVES")) begin
      $shm_open("waves.shm");
      $shm_probe(tb_top, "AS");
    end
  end

endmodule : tb_top