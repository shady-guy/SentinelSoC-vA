`timescale 1ns / 1ps

module otp #(parameter addrwidth=3, parameter public_key_bits=256)(
    input logic clk,
    input logic rst,
    input logic boot_active,

    input logic rd_en,
    input logic [addrwidth-1:0] rd_addr,
    output logic [31:0] rd_data,

    input logic prog_en,
    input logic [addrwidth-1:0] prog_addr,
    input logic prog_data,

    input logic test_mode,   
    output logic otp_lock
);

// OTP storage array 
logic [public_key_bits-1:0] otp_mem;

logic lock_bit;
assign otp_lock = lock_bit;

// secure boot access (32-bit little-endian read)
always_ff @(posedge clk) begin
    if (rst) begin
        rd_data <= 32'h0;  
    end
    else if (boot_active && rd_en) begin
        rd_data <= otp_mem[rd_addr*32 +: 32];
    end
    else begin
        rd_data <= 32'h0;
    end
end

// programming mode (bit-addressable)
always_ff @(posedge clk) begin
    if (rst) begin
        lock_bit <= 1'b0;
    end
    else begin
        // allow programming only in manufacturing mode
        if (prog_en && test_mode && !lock_bit) begin
            otp_mem[prog_addr] <= prog_data;
        end
        // lock command to prevent further programming
        if (prog_en && test_mode &&
            prog_addr == {addrwidth{1'b1}} &&
            prog_data == 1'b1) begin
            lock_bit <= 1'b1;
        end
    end
end

endmodule