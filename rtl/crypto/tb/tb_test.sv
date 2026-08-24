// tb_test.sv
class tb_test extends uvm_test;

  `uvm_component_utils(tb_test)

  tb_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db#(uvm_active_passive_enum)::set(this, "env.agent", "is_active", UVM_ACTIVE);
    env = tb_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    top_virtual_seq seq;
    phase.raise_objection(this);

    seq = top_virtual_seq::type_id::create("seq");
    seq.start(env.agent.sequencer);

    phase.drop_objection(this);
  endtask

endclass : tb_test
