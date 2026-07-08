`timescale 1ns / 1ps
module otp #(
    parameter WORD_ADDR_W    = 3,     // 8 x 32-bit words = 256 bits (read side)
    parameter public_key_bits = 256,
    parameter BIT_ADDR_W     = $clog2(public_key_bits)  // 8 bits: 0..255 (program side)
)(
    input  logic                      clk,
    input  logic                      rst,
    input  logic                      boot_active,
    input  logic                      rd_en,
    input  logic [WORD_ADDR_W-1:0]    rd_addr,
    output logic [31:0]               rd_data,

    input  logic                      prog_en,
    input  logic [BIT_ADDR_W-1:0]     prog_addr,
    input  logic                      prog_data,
    input  logic                      lock_cmd,     // dedicated lock strobe, decoupled from prog_addr
    input  logic                      test_mode,
    output logic                      otp_lock
);

    logic [public_key_bits-1:0] otp_mem;
    logic lock_bit;
    assign otp_lock = lock_bit;

    // secure boot access (32-bit read, word-addressed)
    always_ff @(posedge clk) begin
        if (rst) begin
            rd_data <= 32'h0;
        end else if (boot_active && rd_en) begin
            rd_data <= otp_mem[rd_addr*32 +: 32];
        end else begin
            rd_data <= 32'h0;
        end
    end

    // programming mode (bit-addressable, full 8-bit address space)
    always_ff @(posedge clk) begin
        if (rst) begin
            lock_bit <= 1'b0;
        end else begin
            if (prog_en && test_mode && !lock_bit) begin
                otp_mem[prog_addr] <= prog_data;
            end
            if (lock_cmd && test_mode && !lock_bit) begin
                lock_bit <= 1'b1;
            end
        end
    end
endmodule