// tb_env.sv
class tb_env extends uvm_env;

  `uvm_component_utils(tb_env)

  csr_agent     agent;
  tb_scoreboard scoreboard;
  tb_coverage   coverage;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent      = csr_agent::type_id::create("agent", this);
    scoreboard = tb_scoreboard::type_id::create("scoreboard", this);
    coverage   = tb_coverage::type_id::create("coverage", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    agent.monitor.csr_ap.connect(coverage.csr_wr_export);
    agent.monitor.signature_valid_ap.connect(scoreboard.analysis_export);
    agent.monitor.signature_valid_ap.connect(coverage.sig_valid_export);
  endfunction

endclass : tb_env
