// csr_seq_item.sv
class csr_seq_item extends uvm_sequence_item;

  // START_VERIFY_PULSE: pulses the top-level start_verify_i pin for one
  // cycle (separate handshake from CTRL.start; needed to move the FSM
  // from ST_WAIT_START to ST_ED_START).
  typedef enum bit [1:0] { CSR_WRITE, CSR_READ, START_VERIFY_PULSE } csr_kind_e;

  rand csr_kind_e    kind;
  rand bit [31:0]    addr;
  rand bit [31:0]    wdata;
       bit [31:0]    rdata; // filled in by driver on CSR_READ

  `uvm_object_utils_begin(csr_seq_item)
    `uvm_field_enum(csr_kind_e, kind, UVM_ALL_ON)
    `uvm_field_int(addr,   UVM_ALL_ON)
    `uvm_field_int(wdata,  UVM_ALL_ON)
    `uvm_field_int(rdata,  UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "csr_seq_item");
    super.new(name);
  endfunction

endclass : csr_seq_item
