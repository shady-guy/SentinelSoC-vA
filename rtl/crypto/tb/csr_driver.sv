// csr_driver.sv
class csr_driver extends uvm_driver #(csr_seq_item);

  `uvm_component_utils(csr_driver)

  virtual csr_if.DRIVER vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual csr_if.DRIVER)::get(this, "", "vif", vif))
      `uvm_fatal("CSR_DRV", "virtual csr_if.DRIVER not set in config_db")
  endfunction

  task run_phase(uvm_phase phase);
    // idle defaults
    vif.drv_cb.csr_req         <= 1'b0;
    vif.drv_cb.csr_we          <= 1'b0;
    vif.drv_cb.csr_be          <= 4'hF;
    vif.drv_cb.csr_addr        <= 32'h0;
    vif.drv_cb.csr_wdata       <= 32'h0;
    vif.drv_cb.start_verify    <= 1'b0;

    wait (vif.rst_n === 1'b1);

    forever begin
      csr_seq_item req;
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  task drive_item(csr_seq_item req);
    case (req.kind)
      csr_seq_item::CSR_WRITE: begin
        @(vif.drv_cb);
        vif.drv_cb.csr_req   <= 1'b1;
        vif.drv_cb.csr_we    <= 1'b1;
        vif.drv_cb.csr_be    <= 4'hF;
        vif.drv_cb.csr_addr  <= req.addr;
        vif.drv_cb.csr_wdata <= req.wdata;
        @(vif.drv_cb);
        vif.drv_cb.csr_req   <= 1'b0;
        vif.drv_cb.csr_we    <= 1'b0;
      end

      csr_seq_item::CSR_READ: begin
        @(vif.drv_cb);
        vif.drv_cb.csr_req  <= 1'b1;
        vif.drv_cb.csr_we   <= 1'b0;
        vif.drv_cb.csr_addr <= req.addr;
        @(vif.drv_cb);
        vif.drv_cb.csr_req  <= 1'b0;
        // csr_rvalid_o is registered one cycle behind csr_req_i, so the
        // read data is valid on this same edge (already sampled by cb).
        req.rdata = vif.drv_cb.csr_rdata;
      end

      csr_seq_item::START_VERIFY_PULSE: begin
        @(vif.drv_cb);
        vif.drv_cb.start_verify <= 1'b1;
        @(vif.drv_cb);
        vif.drv_cb.start_verify <= 1'b0;
      end
    endcase
  endtask

endclass : csr_driver
