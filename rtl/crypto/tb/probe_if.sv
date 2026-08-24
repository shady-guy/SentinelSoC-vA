// probe_if.sv
// Coverage-only probe. top_most's main FSM `state` is a plain internal
// signal (not a port), so tb_top taps it hierarchically and feeds it in
// here rather than the coverage collector reaching into the DUT itself.
interface probe_if (input logic clk);
  logic [4:0] fsm_state;
endinterface : probe_if
