// csr_if.sv
// Bundles the OBI-style CSR bus plus the top-level status/boot pins of
// top_most so the whole DUT can be driven/observed through one interface.

interface csr_if (input logic clk, input logic rst_n);

  // CSR bus (Ibex -> top_most)
  logic        csr_req;
  logic        csr_we;
  logic [3:0]  csr_be;
  logic [31:0] csr_addr;
  logic [31:0] csr_wdata;
  logic        csr_gnt;
  logic        csr_rvalid;
  logic [31:0] csr_rdata;
  logic        csr_err;

  // Non-CSR top-level pins
  logic        start_verify;
  logic        boot_active;
  logic        verify_done;
  logic        signature_valid;

  //---------------------------------------------------------------
  // Driver clocking block: drives request-side signals on posedge,
  // samples response-side signals on the following edge.
  //---------------------------------------------------------------
  clocking drv_cb @(posedge clk);
    output csr_req, csr_we, csr_be, csr_addr, csr_wdata, start_verify;
    input  csr_gnt, csr_rvalid, csr_rdata, csr_err;
  endclocking

  //---------------------------------------------------------------
  // Monitor clocking block: passive sampling only.
  //---------------------------------------------------------------
  clocking mon_cb @(posedge clk);
    input csr_req, csr_we, csr_be, csr_addr, csr_wdata,
          csr_gnt, csr_rvalid, csr_rdata, csr_err,
          start_verify, boot_active, verify_done, signature_valid;
  endclocking

  modport DRIVER (clocking drv_cb, input rst_n);
  modport MONITOR (clocking mon_cb, input rst_n);

endinterface : csr_if
