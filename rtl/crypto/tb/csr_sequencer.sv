// csr_sequencer.sv
class csr_sequencer extends uvm_sequencer #(csr_seq_item);
  `uvm_component_utils(csr_sequencer)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass : csr_sequencer
