module sha_ed25519_obi_wrapper (
    input  logic        clk_i,
    input  logic        rst_ni,

    // OBI Slave Interface
    input  logic        req_i,
    output logic        gnt_o,
    input  logic [11:0] addr_i,
    input  logic        we_i,
    input  logic [31:0] wdata_i,
    output logic [31:0] rdata_o,
    output logic        rvalid_o,

    // Crypto Interface
    output logic        start_verify_o,
    input  logic        verify_done_i,
    input  logic        signature_valid_i
);

    // OBI Grant is combinational and always ready
    assign gnt_o = req_i;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            rvalid_o       <= 1'b0;
            rdata_o        <= 32'h0;
            start_verify_o <= 1'b0;
        end else begin
            // Default assignments
            rvalid_o       <= req_i; 
            start_verify_o <= 1'b0; // Self-clearing pulse
            rdata_o        <= 32'h0;

            if (req_i) begin
                if (we_i) begin
                    // Write decode
                    if (addr_i == 12'h000 && wdata_i[0]) begin
                        start_verify_o <= 1'b1;
                    end
                end else begin
                    // Read decode
                    case (addr_i)
                        12'h004: rdata_o <= {30'd0, signature_valid_i, verify_done_i};
                        default: rdata_o <= 32'h0;
                    endcase
                end
            end
        end
    end

endmodule