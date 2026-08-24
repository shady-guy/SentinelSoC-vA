// test_oracle.sv
// Minimal static FIFO so the sequence (which knows the expected KAT
// outcome) can hand it to the scoreboard (which watches the DUT's
// verify_done_o/signature_valid_o pins) without wiring a TLM port
// through a transient sequence object.
class test_oracle;
  static bit expect_q[$];

  static function void push(bit expect_pass);
    expect_q.push_back(expect_pass);
  endfunction

  static function bit pop();
    if (expect_q.size() == 0) begin
      $fatal(1, "TEST_ORACLE: pop() called with empty expect queue");
    end
    return expect_q.pop_front();
  endfunction
endclass : test_oracle
