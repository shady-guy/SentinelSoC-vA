// tb_coverage.sv
`uvm_analysis_imp_decl(_csr_wr)
`uvm_analysis_imp_decl(_sig_valid)

class tb_coverage extends uvm_component;

  `uvm_component_utils(tb_coverage)

  uvm_analysis_imp_csr_wr   #(csr_seq_item, tb_coverage) csr_wr_export;
  uvm_analysis_imp_sig_valid #(bit, tb_coverage)          sig_valid_export;

  virtual probe_if pvif;

  bit [31:0] last_csr_addr;
  bit [31:0] last_csr_wdata;
  bit        last_sig_valid;

  // FSM state encoding mirrors top_most.sv's state_t declaration order
  // (default sequential enum encoding, ST_IDLE = 0).
  typedef enum bit [4:0] {
    ST_IDLE, ST_SHA_CFG_LEN, ST_SHA_CFG_CTRL, ST_SHA_POLL,
    ST_FEED_R,
    ST_OTP_REQ, ST_OTP_LATCH, ST_BLK_POLL_OTP,
    ST_WAIT_DATA, ST_BLK_POLL,
    ST_WAIT_INTR, ST_READ_HASH, ST_READ_HASH_LAST,
    ST_LOAD_REGS, ST_WAIT_START, ST_ED_START, ST_ED_WAIT, ST_DONE
  } fsm_state_e;

  covergroup cg_csr_addr;
    option.per_instance = 1;
    cp_addr: coverpoint last_csr_addr[11:0] {
      bins ctrl    = {12'h000};
      bins status  = {12'h004};
      bins msglen  = {12'h008};
      bins rin     = {12'h00C};
      bins sin     = {12'h010};
      bins datain  = {12'h014};
    }
  endgroup

  covergroup cg_fsm_state;
    option.per_instance = 1;
    cp_state: coverpoint pvif.fsm_state {
      bins states[] = {[0:17]};
    }
  endgroup

  covergroup cg_sig_valid;
    option.per_instance = 1;
    cp_valid: coverpoint last_sig_valid {
      bins verified   = {1};
      bins unverified = {0};
    }
  endgroup

  covergroup cg_ctrl_event;
    option.per_instance = 1;
    cp_abort: coverpoint last_csr_wdata[1] iff (last_csr_addr[11:0] == 12'h000) {
      bins abort_asserted = {1};
    }
    cp_softrst: coverpoint last_csr_wdata[2] iff (last_csr_addr[11:0] == 12'h000) {
      bins softrst_asserted = {1};
    }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    csr_wr_export    = new("csr_wr_export", this);
    sig_valid_export = new("sig_valid_export", this);
    cg_csr_addr   = new();
    cg_fsm_state  = new();
    cg_sig_valid  = new();
    cg_ctrl_event = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual probe_if)::get(this, "", "pvif", pvif))
      `uvm_fatal("TB_COV", "virtual probe_if not set in config_db")
  endfunction

  // From csr_monitor.csr_ap: sample address + ctrl-event coverage.
  function void write_csr_wr(csr_seq_item t);
    last_csr_addr  = t.addr;
    last_csr_wdata = t.wdata;
    cg_csr_addr.sample();
    cg_ctrl_event.sample();
  endfunction

  // From csr_monitor.signature_valid_ap.
  function void write_sig_valid(bit t);
    last_sig_valid = t;
    cg_sig_valid.sample();
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(pvif.fsm_state);
      cg_fsm_state.sample();
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info("TB_COV", $sformatf(
      "Functional coverage: csr_addr=%0.1f%% fsm_state=%0.1f%% sig_valid=%0.1f%% ctrl_event=%0.1f%%",
      cg_csr_addr.get_coverage(), cg_fsm_state.get_coverage(),
      cg_sig_valid.get_coverage(), cg_ctrl_event.get_coverage()), UVM_LOW)
  endfunction

endclass : tb_coverage
