`timescale 1ns / 1ps
module otp #(
    parameter RD_ADDRW     = 3,
    parameter PUB_KEY_BITS = 256,
    parameter PROG_ADDRW   = $clog2(PUB_KEY_BITS) + 1
)(
    input  logic clk,
    input  logic rst,
    input  logic boot_active,
    input  logic rd_en,
    input  logic [RD_ADDRW-1:0] rd_addr,
    output logic [31:0] rd_data,

    input  logic prog_en,
    input  logic [PROG_ADDRW-1:0] prog_addr,
    input  logic prog_data,
    input  logic test_mode,
    output logic otp_lock
);
    logic [PUB_KEY_BITS-1:0] otp_mem;
    logic lock_bit;
    assign otp_lock = lock_bit;

    localparam logic [PROG_ADDRW-1:0] LOCK_SENTINEL = {PROG_ADDRW{1'b1}};

    // Combinational (zero-latency) read — matches the interface top_most's
    // FSM was designed and verified against (ST_OTP_REQ asserts rd_en,
    // ST_OTP_LATCH consumes rd_data on the very next cycle, no extra delay).
    assign rd_data = (boot_active && rd_en) ? otp_mem[rd_addr*32 +: 32] : 32'h0;

    // Programming/lock path unchanged — sequential is correct here,
    // this isn't on the boot-time critical timing path.
    always_ff @(posedge clk) begin
        if (rst) begin
            lock_bit <= 1'b0;
        end else begin
            if (prog_en && test_mode && !lock_bit && prog_addr < PUB_KEY_BITS)
                otp_mem[prog_addr] <= prog_data;
            if (prog_en && test_mode && prog_addr == LOCK_SENTINEL && prog_data == 1'b1)
                lock_bit <= 1'b1;
        end
    end
endmodule