module tb_sha_ed25519_obi_wrapper;
    logic        clk;
    logic        rst_n;
    logic        req;
    logic        gnt;
    logic [11:0] addr;
    logic        we;
    logic [31:0] wdata;
    logic [31:0] rdata;
    logic        rvalid;
    logic        start_verify;
    logic        verify_done;
    logic        signature_valid;

    sha_ed25519_obi_wrapper dut (
        .clk_i(clk), .rst_ni(rst_n),
        .req_i(req), .gnt_o(gnt), .addr_i(addr), .we_i(we),
        .wdata_i(wdata), .rdata_o(rdata), .rvalid_o(rvalid),
        .start_verify_o(start_verify), .verify_done_i(verify_done),
        .signature_valid_i(signature_valid)
    );

    always #5 clk = ~clk;

    logic error_flag = 0;

    initial begin
        clk = 0; rst_n = 0; req = 0; we = 0; addr = 0; wdata = 0;
        verify_done = 0; signature_valid = 0;
        #20 rst_n = 1;

        // Test 1: Write to CRYPTO_CTRL (Pulse check)
        @(posedge clk);
        req = 1; we = 1; addr = 12'h000; wdata = 32'h1;
        @(posedge clk);
        req = 0; we = 0;
        if (start_verify !== 1'b1) begin $display("FAIL: Pulse missing"); error_flag = 1; end
        @(posedge clk);
        if (start_verify !== 1'b0) begin $display("FAIL: Pulse didn't clear"); error_flag = 1; end

        // Test 2: Read CRYPTO_STATUS
        verify_done = 1; signature_valid = 1;
        @(posedge clk);
        req = 1; we = 0; addr = 12'h004;
        @(posedge clk);
        req = 0;
        if (rdata !== 32'h3 || rvalid !== 1'b1) begin $display("FAIL: Status read"); error_flag = 1; end

        if (!error_flag) $display("SUCCESS: obi_wrapper verified.");
        else $display("FAILURE: obi_wrapper tests failed.");
        $finish;
    end
endmodule