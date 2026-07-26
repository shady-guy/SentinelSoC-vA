`timescale 1ns/1ps

module tb_top_most_firmware;

    logic        clk = 0, rst_n = 0;

    // -----------------------------------------------------------------
    // CSR (OBI-style flat) slave port driven by this TB, standing in
    // for Ibex/BootROM
    // -----------------------------------------------------------------
    logic        csr_req_i, csr_we_i;
    logic [ 3:0] csr_be_i;
    logic [31:0] csr_addr_i, csr_wdata_i;
    logic        csr_gnt_o, csr_rvalid_o;
    logic [31:0] csr_rdata_o;
    logic        csr_err_o;

    logic        start_verify;
    logic [2:0]  otp_addr;
    logic        otp_rd_en;
    logic [31:0] otp_data;
    logic        boot_active;
    logic        verify_done, sig_valid;

    always #5 clk = ~clk;

    // -----------------------------------------------------------------
    // CSR address map — must match top_most.sv
    // -----------------------------------------------------------------
    localparam logic [11:0] CTRL_OFF    = 12'h000;
    localparam logic [11:0] STATUS_OFF  = 12'h004;
    localparam logic [11:0] MSGLEN_OFF  = 12'h008;
    localparam logic [11:0] RIN_OFF     = 12'h00C;
    localparam logic [11:0] SIN_OFF     = 12'h010;
    localparam logic [11:0] DATAIN_OFF  = 12'h014;

    localparam int ST_BUSY  = 0;
    localparam int ST_READY = 1;
    localparam int ST_DONE  = 2;
    localparam int ST_VALID = 3;

    // -----------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------
    top_most dut (
        .clk               (clk),
        .rst_n             (rst_n),

        .csr_req_i         (csr_req_i),
        .csr_we_i          (csr_we_i),
        .csr_be_i          (csr_be_i),
        .csr_addr_i        (csr_addr_i),
        .csr_wdata_i       (csr_wdata_i),
        .csr_gnt_o         (csr_gnt_o),
        .csr_rvalid_o      (csr_rvalid_o),
        .csr_rdata_o       (csr_rdata_o),
        .csr_err_o         (csr_err_o),

        .start_verify_i    (start_verify),
        .otp_addr_o        (otp_addr),
        .otp_rd_en_o       (otp_rd_en),
        .otp_data_i        (otp_data),
        .boot_active_o     (boot_active),
        .verify_done_o     (verify_done),
        .signature_valid_o (sig_valid)
    );

    // -----------------------------------------------------------------
    // Real OTP module — driven directly (not via CSR)
    // -----------------------------------------------------------------
    logic       otp_prog_en, otp_prog_data, otp_test_mode;
    logic [8:0] otp_prog_addr;

    otp #(.RD_ADDRW(3), .PUB_KEY_BITS(256)) u_otp (
        .clk(clk), .rst(~rst_n), .boot_active(boot_active),
        .rd_en(otp_rd_en), .rd_addr(otp_addr), .rd_data(otp_data),
        .prog_en(otp_prog_en), .prog_addr(otp_prog_addr),
        .prog_data(otp_prog_data), .test_mode(otp_test_mode), .otp_lock()
    );

    // -----------------------------------------------------------------
    // Task: bit-serial OTP programming from pubkey.mem, then lock.
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
            otp_prog_addr = 9'h1FF;            // all-ones, out of valid 0-255 range
            otp_prog_data = 1'b1;
            @(negedge clk); otp_prog_en = 1'b0;
            otp_test_mode = 1'b0;
            $fclose(fd);
        end
    endtask

    // -----------------------------------------------------------------
    // CSR bus primitives.
    // gnt is combinational/immediate (csr_gnt_o = csr_req_i), and
    // rvalid_o/rdata_o are registered one cycle behind req. Drive
    // req/we/addr/wdata from a negedge so they're stable across the
    // posedge the DUT samples on, then sample the registered response
    // from the following negedge.
    // -----------------------------------------------------------------
    task automatic csr_write(input logic [11:0] addr, input logic [31:0] data);
        begin
            @(negedge clk);
            csr_req_i   = 1'b1;
            csr_we_i    = 1'b1;
            csr_be_i    = 4'hF;
            csr_addr_i  = {20'h0, addr};
            csr_wdata_i = data;
            @(negedge clk);   // holds req/we/addr/wdata stable across one posedge
            csr_req_i   = 1'b0;
            csr_we_i    = 1'b0;
        end
    endtask

    task automatic csr_read(input logic [11:0] addr, output logic [31:0] data);
        begin
            @(negedge clk);
            csr_req_i  = 1'b1;
            csr_we_i   = 1'b0;
            csr_be_i   = 4'hF;
            csr_addr_i = {20'h0, addr};
            @(negedge clk);   // rvalid_o/rdata_o now reflect this request
            data = csr_rdata_o;
            csr_req_i  = 1'b0;
        end
    endtask

    // -----------------------------------------------------------------
    // Task: drive R_IN x8 / S_IN x8 / MSG_LEN / CTRL.start / DATA_IN
    // from flash.mem, mirroring the BootROM pseudocode:
    //   file layout: [word0 = total word count fed to SHA (R+pubkey+msg)]
    //                [8 words R] [8 words S] [remaining words = message]
    //
    // corrupt_en flips one bit of message word corrupt_word_idx
    // (0-indexed within the message body only — R/S/pubkey/len stay
    // untouched) to simulate tampered/wrong firmware while keeping a
    // signature that was valid for the ORIGINAL bytes.
    // -----------------------------------------------------------------
    int unsigned data_wait_iters = 0; // counts extra poll spins on DATA_IN handshake

// -----------------------------------------------------------------
    // Task: drive R_IN x8 / S_IN x8 / MSG_LEN / CTRL.start / DATA_IN
    // -----------------------------------------------------------------
    localparam int unsigned MAX_STATUS_SPINS = 100_000; // ~1ms of polling —
                                                          // generous vs the
                                                          // ~113-cycle SHA
                                                          // block latency

    task automatic drive_flash_mem(string path, input bit corrupt_en = 0,
                                    input int corrupt_word_idx = 0);
        integer fd, code;
        logic [31:0] word;
        logic [31:0] msg_len_word;
        logic [31:0] r_words [0:7];
        logic [31:0] s_words [0:7];
        logic [31:0] status;
        int i;
        int spins;
        int msg_word_idx;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) $fatal(1, "Cannot open %s", path);

            code = $fscanf(fd, "%h\n", msg_len_word);
            if (code != 1) $fatal(1, "flash.mem missing length word");
            $display("[%0t] msg_len_word = %0d words", $time, msg_len_word);

            for (i = 0; i < 8; i++) begin
                code = $fscanf(fd, "%h\n", word);
                if (code != 1) $fatal(1, "flash.mem short on R words");
                r_words[i] = word;
            end
            for (i = 0; i < 8; i++) begin
                code = $fscanf(fd, "%h\n", word);
                if (code != 1) $fatal(1, "flash.mem short on S words");
                s_words[i] = word;
            end

            for (i = 0; i < 8; i++) csr_write(RIN_OFF, r_words[i]);
            for (i = 0; i < 8; i++) csr_write(SIN_OFF, s_words[i]);
            csr_write(MSGLEN_OFF, msg_len_word);
            $display("[%0t] R_IN/S_IN/MSG_LEN written, dut.state=%0d", $time, dut.state);

            csr_write(CTRL_OFF, 32'h1); // start
            $display("[%0t] CTRL.start written, dut.state=%0d", $time, dut.state);

            msg_word_idx = 0;
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%h\n", word);
                if (code != 1) continue;

                if (corrupt_en && msg_word_idx == corrupt_word_idx) begin
                    $display("INJECTING CORRUPTION: msg word %0d  %h -> %h",
                              msg_word_idx, word, word ^ 32'h0000_0001);
                    word = word ^ 32'h0000_0001;
                end

                spins = 0;
                csr_read(STATUS_OFF, status);
                while (!status[ST_READY]) begin
                    spins++;
                    if (spins == MAX_STATUS_SPINS) begin
                        $display("STUCK waiting for STATUS.ready_for_word at msg_word_idx=%0d",
                                  msg_word_idx);
                        $display("  dut.state        = %0d", dut.state);
                        $display("  dut.data_pending  = %0b", dut.data_pending);
                        $display("  dut.blk_ptr       = %0d", dut.blk_ptr);
                        $display("  dut.sha_fed       = %0d", dut.sha_fed);
                        $display("  dut.sha_len_reg   = %0d", dut.sha_len_reg);
                        $display("  dut.otp_idx       = %0d", dut.otp_idx);
                        $display("  dut.r_idx         = %0d", dut.r_idx);
                        $fatal(1, "drive_flash_mem: STATUS poll exceeded %0d iterations",
                                MAX_STATUS_SPINS);
                    end
                    csr_read(STATUS_OFF, status);
                end
                if (spins > 0) data_wait_iters += spins;

                csr_write(DATAIN_OFF, word);
                msg_word_idx++;
                if (msg_word_idx % 1000 == 0)
                    $display("[%0t] fed %0d message words", $time, msg_word_idx);
            end

            $fclose(fd);
        end
    endtask

    // -----------------------------------------------------------------
    // Task: full hardware reset + OTP re-program, so a second scenario
    // can run cleanly in the same simulation. sha512_top / top_ed25519
    // have no standalone soft-reset of their own — CTRL.soft_reset only
    // rewinds top_most's FSM, not the SHA/ED25519 IP's internal state —
    // so a real rst_n pulse is the safe way to get a clean slate between
    // back-to-back test cases.
    // -----------------------------------------------------------------
    task automatic reset_and_reprogram_otp();
        begin
            rst_n = 0;
            repeat(4) @(posedge clk);
            @(negedge clk); rst_n = 1;
            repeat(2) @(posedge clk);
            program_otp_from_file("rtl/crypto/scripts/mems/pubkey.mem");
            repeat(5) @(posedge clk);
        end
    endtask

    int fail = 0;

    initial begin
        csr_req_i = 0; csr_we_i = 0; csr_be_i = 4'h0;
        csr_addr_i = 0; csr_wdata_i = 0;
        start_verify = 0;
        otp_prog_en = 0; otp_prog_addr = 0; otp_prog_data = 0; otp_test_mode = 0;

        // ===============================================================
        // Scenario 1: correct firmware, correct R/S/pubkey — expect PASS
        // ===============================================================
        $display("==================================================");
        $display("Starting Scenario 1: valid firmware, expect SUCCESS...");
        $display("==================================================");

        @(negedge clk); rst_n = 1;   // negedge avoids racing otp's sync-reset flop
        repeat(2) @(posedge clk);

        program_otp_from_file("rtl/crypto/scripts/mems/pubkey.mem");
        repeat(5) @(posedge clk);

        drive_flash_mem("rtl/crypto/scripts/mems/flash.mem");

        // Allow time for SHA processing and OTP reads after the last
        // DATA_IN write. Confirmed sufficient for a 512KB firmware run;
        // re-check if firmware size changes substantially.
        repeat(20000) @(posedge clk);

        @(posedge clk); #1;
        start_verify = 1;
        @(posedge clk); #1;
        start_verify = 0;

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
            $display("FAILURE: boot_active did not deassert after verify_done (scenario 1)");
            fail++;
        end else begin
            $display("PASS: boot_active correctly deasserted after verify_done (scenario 1)");
        end

        if (data_wait_iters == 0) begin
            $display("NOTE: STATUS.ready_for_word was always set on first poll —");
            $display("      the wait side of the handshake was never exercised.");
        end else begin
            $display("PASS: DATA_IN handshake made the TB poll-spin %0d time(s) —",
                      data_wait_iters);
            $display("      CPU-paced ready/busy backpressure is real.");
        end

        // ===============================================================
        // Scenario 2: same valid R/S/pubkey/MSG_LEN, but one word of the
        // firmware body is bit-flipped before hashing. Signature was
        // computed over the ORIGINAL firmware, so this must fail.
        // ===============================================================
        $display("==================================================");
        $display("Starting Scenario 2: corrupted firmware, expect FAILURE...");
        $display("==================================================");

        reset_and_reprogram_otp();

        drive_flash_mem("rtl/crypto/scripts/mems/flash.mem",
                         .corrupt_en(1), .corrupt_word_idx(0));

        repeat(20000) @(posedge clk);

        @(posedge clk); #1;
        start_verify = 1;
        @(posedge clk); #1;
        start_verify = 0;

        wait(verify_done);
        @(posedge clk);

        $display("==================================================");
        if (!sig_valid) begin
            $display("SUCCESS: signature_valid=0, corrupted firmware correctly rejected");
        end else begin
            $display("FAILURE: signature_valid=1, corrupted firmware WAS ACCEPTED — bug");
            fail++;
        end

        if (boot_active) begin
            $display("FAILURE: boot_active did not deassert after verify_done (scenario 2)");
            fail++;
        end else begin
            $display("PASS: boot_active correctly deasserted after verify_done (scenario 2)");
        end

        $display("==================================================");
        if (fail == 0)
            $display("SUCCESS: all functional tests passed (both scenarios)");
        else
            $display("FAILURE: %0d test(s) failed across both scenarios", fail);

        $finish;
    end

    initial #400000000 begin
        $display("FAILURE: timeout waiting for verify_done");
        $finish;
    end

endmodule