`timescale 1ns/1ps

module tb_top_most_firmware;

    logic        clk = 0;
    logic        rst_n = 0;

    // -----------------------------------------------------------------
    // CSR Interface Signals
    // -----------------------------------------------------------------
    logic        csr_req = 0;
    logic        csr_we = 0;
    logic [3:0]  csr_be = 4'hF;
    logic [31:0] csr_addr = 0;
    logic [31:0] csr_wdata = 0;
    logic        csr_gnt;
    logic        csr_rvalid;
    logic [31:0] csr_rdata;
    logic        csr_err;

    // -----------------------------------------------------------------
    // Legacy / Sideband Signals
    // -----------------------------------------------------------------
    logic        start_verify = 0; // Unused in CSR mode, tied low
    logic [2:0]  otp_addr;
    logic        otp_rd_en;
    logic [31:0] otp_data;
    logic        boot_active;
    logic        verify_done;
    logic        sig_valid;

    always #5 clk = ~clk;

    // -----------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------
    top_most dut (
        .clk              (clk),
        .rst_n            (rst_n),

        .csr_req_i        (csr_req),
        .csr_we_i         (csr_we),
        .csr_be_i         (csr_be),
        .csr_addr_i       (csr_addr),
        .csr_wdata_i      (csr_wdata),
        .csr_gnt_o        (csr_gnt),
        .csr_rvalid_o     (csr_rvalid),
        .csr_rdata_o      (csr_rdata),
        .csr_err_o        (csr_err),

        .start_verify_i   (start_verify),
        .otp_addr_o       (otp_addr),
        .otp_rd_en_o      (otp_rd_en),
        .otp_data_i       (otp_data),
        .boot_active_o    (boot_active),
        .verify_done_o    (verify_done),
        .signature_valid_o(sig_valid)
    );

    // -----------------------------------------------------------------
    // Real OTP module
    // -----------------------------------------------------------------
    logic       otp_prog_en=0, otp_prog_data=0, otp_test_mode=0;
    logic [8:0] otp_prog_addr=0;

    otp #(.RD_ADDRW(3), .PUB_KEY_BITS(256)) u_otp (
        .clk         (clk), 
        .rst         (~rst_n), 
        .boot_active (boot_active),
        .rd_en       (otp_rd_en), 
        .rd_addr     (otp_addr), 
        .rd_data     (otp_data),
        .prog_en     (otp_prog_en), 
        .prog_addr   (otp_prog_addr),
        .prog_data   (otp_prog_data), 
        .test_mode   (otp_test_mode), 
        .otp_lock    ()
    );

    // -----------------------------------------------------------------
    // CSR Bus Access Tasks
    // -----------------------------------------------------------------
    task automatic csr_write(input [31:0] addr, input [31:0] data);
    begin
        @(posedge clk);
        csr_req   <= 1'b1;
        csr_we    <= 1'b1;
        csr_addr  <= addr;
        csr_wdata <= data;
        csr_be    <= 4'hF;
        
        while (!csr_gnt) @(posedge clk);
        csr_req <= 1'b0;
        csr_we  <= 1'b0;
    end
    endtask

    task automatic csr_read(input [31:0] addr, output [31:0] data);
    begin
        @(posedge clk);
        csr_req  <= 1'b1;
        csr_we   <= 1'b0;
        csr_addr <= addr;
        
        while (!csr_gnt) @(posedge clk);
        csr_req <= 1'b0;
        
        while (!csr_rvalid) @(posedge clk);
        data = csr_rdata;
    end
    endtask

    // -----------------------------------------------------------------
    // Task: Bit-serial OTP programming
    // -----------------------------------------------------------------
    task automatic program_otp_from_file(string path);
        integer fd, code;
        logic [31:0] word;
        int w, b;
    begin
        fd = $fopen(path, "r");
        if (fd == 0) $fatal(1, "Cannot open %s", path);
        otp_test_mode = 1'b1;
        w = 0;
        while (!$feof(fd)) begin
            code = $fscanf(fd, "%h\n", word);
            if (code != 1) continue;
            for (b = 0; b < 32; b++) begin
                @(negedge clk);
                otp_prog_en   = 1'b1;
                otp_prog_addr = w*32 + b;
                otp_prog_data = word[b];
            end
            w++;
        end
        @(negedge clk); otp_prog_en = 1'b0;
        @(negedge clk);                    // lock
        otp_prog_en   = 1'b1;
        otp_prog_addr = 9'h1FF;            // out of valid 0-255 range
        otp_prog_data = 1'b1;
        @(negedge clk); otp_prog_en = 1'b0;
        otp_test_mode = 1'b0;
        $fclose(fd);
    end
    endtask

    // -----------------------------------------------------------------
    // Task: Firmware Loading via CSR (Firmware execution model)
    // -----------------------------------------------------------------
    int poll_wait_cycles = 0;

    task automatic load_firmware_via_csr(string path);
        integer fd, code;
        logic [31:0] word;
        logic [31:0] status_val;
        int i;
        
        localparam logic [31:0] CTRL_OFF   = 32'h000;
        localparam logic [31:0] STATUS_OFF = 32'h004;
        localparam logic [31:0] MSGLEN_OFF = 32'h008;
        localparam logic [31:0] RIN_OFF    = 32'h00C;
        localparam logic [31:0] SIN_OFF    = 32'h010;
        localparam logic [31:0] DATAIN_OFF = 32'h014;
    begin
        fd = $fopen(path, "r");
        if (fd == 0) $fatal(1, "Cannot open %s", path);

        // 1. Read Word 0: SHA Length
        code = $fscanf(fd, "%h\n", word);
        csr_write(MSGLEN_OFF, word);

        // 2. Read Words 1-8: R_IN
        for (i = 0; i < 8; i++) begin
            code = $fscanf(fd, "%h\n", word);
            csr_write(RIN_OFF, word);
        end

        // 3. Read Words 9-16: S_IN
        for (i = 0; i < 8; i++) begin
            code = $fscanf(fd, "%h\n", word);
            csr_write(SIN_OFF, word);
        end

        // 4. Start Orchestrator (Write 1 to CTRL.start)
        csr_write(CTRL_OFF, 32'h0000_0001);

        // 5. Stream Message Body
        while (!$feof(fd)) begin
            code = $fscanf(fd, "%h\n", word);
            if (code != 1) continue;
            
            // Poll STATUS.ready_for_word (Bit 1)
            do begin
                csr_read(STATUS_OFF, status_val);
                if ((status_val & 32'h2) == 0) poll_wait_cycles++;
            end while ((status_val & 32'h2) == 0);
            
            // Write word to DATA_IN
            csr_write(DATAIN_OFF, word);
        end

        $fclose(fd);
    end
    endtask

    // -----------------------------------------------------------------
    // Main Test Sequence
    // -----------------------------------------------------------------
    int fail = 0;

    initial begin
        $display("==================================================");
        $display("Starting CSR-Driven Secure Boot Simulation...");
        $display("==================================================");

        @(negedge clk); rst_n = 1;
        repeat(2) @(posedge clk);

        // 1. Program OTP 
        program_otp_from_file("rtl/crypto/scripts/mems/pubkey.mem");
        repeat(5) @(posedge clk);

        // 2. Emulate Firmware feeding data via CSR
        load_firmware_via_csr("rtl/crypto/scripts/mems/flash.mem");

        // Wait for verify_done_o from the top-level port
        wait(verify_done);
        @(posedge clk);

        $display("==================================================");
        if (sig_valid) begin
            $display("SUCCESS: signature_valid=1, signature verified correctly");
        end else begin
            $display("FAILURE: signature_valid=0, verification failed on valid signature");
            fail++;
        end

        if (boot_active) begin
            $display("FAILURE: boot_active did not deassert after verify_done");
            fail++;
        end else begin
            $display("PASS: boot_active correctly deasserted after verify_done");
        end

        $display("NOTE: Firmware experienced %0d polling wait cycles while writing DATA_IN.", poll_wait_cycles);

        if (fail == 0)
            $display("SUCCESS: all functional tests passed");
        else
            $display("FAILURE: %0d test(s) failed", fail);

        $finish;
    end

    // Failsafe timeout
    initial #200000000 begin
        $display("FAILURE: timeout waiting for verify_done");
        $finish;
    end

endmodule