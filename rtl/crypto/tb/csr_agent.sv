// csr_agent.sv
class csr_agent extends uvm_agent;

  `uvm_component_utils(csr_agent)

  csr_driver    driver;
  csr_sequencer sequencer;
  csr_monitor   monitor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    monitor = csr_monitor::type_id::create("monitor", this);
    if (get_is_active() == UVM_ACTIVE) begin
      driver    = csr_driver::type_id::create("driver", this);
      sequencer = csr_sequencer::type_id::create("sequencer", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (get_is_active() == UVM_ACTIVE)
      driver.seq_item_port.connect(sequencer.seq_item_export);
  endfunction

endclass : csr_agent
