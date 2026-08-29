// reset_if.sv
// top_most is a boot-time-only design (per its own comment: no retry
// semantics needed). It's meant to verify exactly one signature per
// reset cycle. Running multiple vectors in one simulation therefore
// requires a real reset between each one -- this interface provides that.

interface reset_if (input logic clk);

  logic rst_n = 1'b0;

  task automatic do_reset(input int unsigned cycles = 5);
    rst_n = 1'b0;
    repeat (cycles) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
  endtask

endinterface : reset_if