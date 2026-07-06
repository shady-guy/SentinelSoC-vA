module tb_top_most;
    logic        clk, rst_n, stream_valid, start_verify_i;
    logic [31:0] stream_data;
    logic [2:0]  otp_addr;
    logic        otp_rd_en, verify_done, signature_valid, boot_active;
    logic [31:0] otp_data;
    
    // Mocks
    logic ext_we, start_verify_ed, verify_done_ed, signature_valid_ed, sha_we, sha_intr;
    logic [1:0] data_sel;
    logic [31:0] ext_data_1, sha_wdata, sha_rdata;
    logic [4:0] ext_dest_sel;
    logic [7:0] sha_addr;

    top_most dut (.*);

    always #5 clk = ~clk;

    logic error_flag = 0;

    initial begin
        clk = 0; rst_n = 0; stream_valid = 0; stream_data = 0;
        start_verify_i = 0; otp_data = 0; verify_done_ed = 0; 
        signature_valid_ed = 0; sha_intr = 0; sha_rdata = 0;
        
        #20 rst_n = 1;

        // Test 1: Stream classification and OTP trigger
        for (int i = 0; i <= 16; i++) begin
            @(posedge clk);
            stream_valid = 1; stream_data = i;
        end
        @(posedge clk);
        stream_valid = 0;

        // Verify OTP read triggers
        wait(otp_rd_en);
        @(posedge clk);
        if (otp_addr !== 3'b000) begin $display("FAIL: OTP Addr"); error_flag = 1; end
        
        // Let OTP finish
        #100;

        // Test 2: ED25519 Register Loading triggered by SHA Intr
        @(posedge clk);
        sha_intr = 1; start_verify_i = 1; // Assert pending start simultaneously
        @(posedge clk);
        sha_intr = 0; start_verify_i = 0;

        wait(ext_we);
        #170; // 17 cycles of loading
        @(posedge clk);
        if (ext_we !== 1'b0) begin $display("FAIL: Load didn't end"); error_flag = 1; end
        
        // Check if start_verify latched and fired
        @(posedge clk);
        if (start_verify_ed !== 1'b1) begin $display("FAIL: ED start missing"); error_flag = 1; end

        if (!error_flag) $display("SUCCESS: top_most flow verified.");
        else $display("FAILURE: top_most tests failed.");
        $finish;
    end
endmodule