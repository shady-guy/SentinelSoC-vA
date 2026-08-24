// csr_monitor.sv
class csr_seq_item_mon extends csr_seq_item;
  `uvm_object_utils(csr_seq_item_mon)
  function new(string name = "csr_seq_item_mon");
    super.new(name);
  endfunction
endclass

class csr_monitor extends uvm_monitor;

  `uvm_component_utils(csr_monitor)

  virtual csr_if.MONITOR vif;

  uvm_analysis_port #(csr_seq_item)  csr_ap;     // observed CSR writes
  uvm_analysis_port #(bit)           verify_done_ap;   // pulses w/ signature_valid sampled
  uvm_analysis_port #(bit)           signature_valid_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    csr_ap             = new("csr_ap", this);
    verify_done_ap      = new("verify_done_ap", this);
    signature_valid_ap  = new("signature_valid_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual csr_if.MONITOR)::get(this, "", "vif", vif))
      `uvm_fatal("CSR_MON", "virtual csr_if.MONITOR not set in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    bit prev_verify_done;
    prev_verify_done = 1'b0;

    forever begin
      @(vif.mon_cb);

      // Report CSR write transactions
      if (vif.mon_cb.csr_req && vif.mon_cb.csr_we) begin
        csr_seq_item_mon item = csr_seq_item_mon::type_id::create("item");
        item.kind  = csr_seq_item::CSR_WRITE;
        item.addr  = vif.mon_cb.csr_addr;
        item.wdata = vif.mon_cb.csr_wdata;
        csr_ap.write(item);
      end

      // Report verify_done rising edge (one-shot pulse from DUT)
      if (vif.mon_cb.verify_done && !prev_verify_done) begin
        verify_done_ap.write(1'b1);
        signature_valid_ap.write(vif.mon_cb.signature_valid);
      end
      prev_verify_done = vif.mon_cb.verify_done;
    end
  endtask

endclass : csr_monitor
