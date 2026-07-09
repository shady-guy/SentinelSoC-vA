`timescale 1ns/1ps

module tb_top_most_firmware;

    logic        clk=0, rst_n=0;
    logic [31:0] stream_data_i;
    logic        stream_valid_i;
    logic        start_verify;
    logic [2:0]  otp_addr;
    logic        otp_rd_en;
    logic [31:0] otp_data;
    logic        boot_active;
    logic        verify_done, sig_valid;

    always #5 clk = ~clk;

    // -----------------------------------------------------------------
    // DUT
    // -----------------------------------------------------------------
    top_most dut (
        .clk(clk), .rst_n(rst_n),
        .stream_data_i(stream_data_i), .stream_valid_i(stream_valid_i),
        .start_verify_i(start_verify),
        .otp_addr_o(otp_addr), .otp_rd_en_o(otp_rd_en), .otp_data_i(otp_data),
        .boot_active_o(boot_active),
        .verify_done_o(verify_done), .signature_valid_o(sig_valid)
    );

    // -----------------------------------------------------------------
    // Real OTP module (corrected version) — replaces old otp_mem array
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
    // Task: bit-serial OTP programming from pubkey.mem, then lock
    // FIX (Bug 1): drive on @(negedge clk) instead of @(posedge clk).
    // The otp module samples otp_prog_en/addr/data on posedge clk, so
    // driving those same signals on posedge raced the sampling flop and
    // otp_mem ended up all-X. negedge gives a full half-cycle of setup,
    // matching how stream_flash_mem already drives stream_data_i/valid_i.
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
    // Task: FIFO-aware flash streaming from flash.mem
    // -----------------------------------------------------------------
    task automatic stream_flash_mem(string path);
        integer fd, code;
        logic [31:0] word;
        begin
            fd = $fopen(path, "r");
            if (fd == 0) $fatal(1, "Cannot open %s", path);
            stream_valid_i = 1'b0;
            while (!$feof(fd)) begin
                code = $fscanf(fd, "%h\n", word);
                if (code != 1) continue;
                while (dut.fifo_full) @(posedge clk);   // wait for room
                @(negedge clk);
                stream_data_i  = word;
                stream_valid_i = 1'b1;
            end
            @(negedge clk);
            stream_valid_i = 1'b0;
            $fclose(fd);
        end
    endtask

    // =========================================================================
    // Silent counter — confirms backpressure path is exercised, no per-event
    // printing. Debug FSM/register/event monitors removed (were for bring-up
    // only); only the final PASS/FAIL summary below is printed now.
    // =========================================================================
    int fifo_full_asserts = 0;
    always @(posedge dut.fifo_full) begin
        fifo_full_asserts++;
    end
    // =========================================================================

    int fail = 0;

    initial begin
        $display("==================================================");
        $display("Starting Secure Boot Simulation (Firmware TB)...");
        $display("==================================================");

        stream_data_i=0; stream_valid_i=0; start_verify=0;
        otp_prog_en=0; otp_prog_addr=0; otp_prog_data=0; otp_test_mode=0;

        @(negedge clk); rst_n=1;   // Bug 1b fix: negedge avoids racing otp's
                                   // synchronous-reset flop on the same posedge
        repeat(2) @(posedge clk);

        // 1. Program OTP with the pubkey generated by sign_firmware.py / build_mem.py
        program_otp_from_file("rtl/crypto/scripts/mems/pubkey.mem");

        repeat(5) @(posedge clk);

        // 2. Stream flash.mem (sha_len + R + S + firmware), FIFO-safe
        stream_flash_mem("rtl/crypto/scripts/mems/flash.mem");

        // Allow time for SHA processing and OTP reads after streaming completes.
        // Confirmed sufficient for a 512KB firmware run; re-check if firmware
        // size changes substantially.
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
            $display("FAILURE: boot_active did not deassert after verify_done");
            fail++;
        end else begin
            $display("PASS: boot_active correctly deasserted after verify_done");
        end

        if (fifo_full_asserts == 0) begin
            $display("NOTE: dut.fifo_full never asserted — backpressure path in");
            $display("      stream_flash_mem was never exercised for this run.");
        end else begin
            $display("PASS: dut.fifo_full asserted %0d time(s) — backpressure is real.", fifo_full_asserts);
        end

        if (fail == 0)
            $display("SUCCESS: all functional tests passed");
        else
            $display("FAILURE: %0d test(s) failed", fail);

        $finish;
    end

    initial #200000000 begin
        $display("FAILURE: timeout waiting for verify_done");
        $finish;
    end

endmodule