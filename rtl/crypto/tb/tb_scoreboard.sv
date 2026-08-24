// tb_scoreboard.sv
class tb_scoreboard extends uvm_subscriber #(bit);

  `uvm_component_utils(tb_scoreboard)

  int unsigned checks_done;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    checks_done = 0;
  endfunction

  // Called once per verify_done pulse with the sampled signature_valid_o
  // value (see csr_monitor.signature_valid_ap).
  function void write(bit t);
    bit expected;
    expected = test_oracle::pop();
    checks_done++;

    if (t !== expected)
      `uvm_error("SCOREBOARD",
        $sformatf("PIN CHECK MISMATCH #%0d: signature_valid_o=%0b, expected=%0b",
                   checks_done, t, expected))
    else
      `uvm_info("SCOREBOARD",
        $sformatf("PIN CHECK #%0d OK: signature_valid_o=%0b matches expected",
                   checks_done, t), UVM_LOW)
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCOREBOARD",
      $sformatf("Total pin-level checks performed: %0d", checks_done), UVM_LOW)
  endfunction

endclass : tb_scoreboard
