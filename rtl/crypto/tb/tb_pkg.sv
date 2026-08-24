// tb_pkg.sv
`include "uvm_macros.svh"

package tb_pkg;
  import uvm_pkg::*;
  import rfc8032_vectors_pkg::*;

  `include "test_oracle.sv"
  `include "csr_seq_item.sv"
  `include "csr_driver.sv"
  `include "csr_monitor.sv"
  `include "csr_sequencer.sv"
  `include "csr_agent.sv"
  `include "csr_seq_lib.sv"
  `include "tb_scoreboard.sv"
  `include "tb_coverage.sv"
  `include "tb_env.sv"
  `include "tb_test.sv"

endpackage : tb_pkg
