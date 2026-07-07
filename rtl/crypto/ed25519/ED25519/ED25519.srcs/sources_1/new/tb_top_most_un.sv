`timescale 1ns/1ps

module tb_top_most;

    logic        clk=0, rst_n=0;
    logic [31:0] stream_data;
    logic        stream_valid;
    logic        start_verify;
    logic [2:0]  otp_addr;
    logic        otp_rd_en;
    logic [31:0] otp_data;
    logic        boot_active;
    logic        verify_done, sig_valid;

    always #5 clk = ~clk;

    // OTP model
    logic [31:0] otp_mem [0:7];
    initial begin
        // Restored to exact original values
        otp_mem[0] = 32'h65aca07e;
        otp_mem[1] = 32'hdafd4c58;
        otp_mem[2] = 32'had156f5a;
        otp_mem[3] = 32'hb8c47add;
        otp_mem[4] = 32'h5f1a6036;
        otp_mem[5] = 32'h339133e1;
        otp_mem[6] = 32'h60edfa65;
        otp_mem[7] = 32'h4087b234;
    end

    // Combinational OTP Read Model (Zero Latency, No 'X's)
    assign otp_data = otp_rd_en ? otp_mem[otp_addr] : 32'h0;

    top_most dut (
        .clk(clk), .rst_n(rst_n),
        .stream_data_i(stream_data), .stream_valid_i(stream_valid),
        .start_verify_i(start_verify),
        .otp_addr_o(otp_addr), .otp_rd_en_o(otp_rd_en), .otp_data_i(otp_data),
        .boot_active_o(boot_active),
        .verify_done_o(verify_done), .signature_valid_o(sig_valid)
    );

    // Flash Data
    logic [31:0] flash [0:24];
    initial begin
        flash[0]  = 32'd24; 
        
        // Fix: Swapped the 8-word blocks for R and S, keeping original word ordering
        // R Vector
        flash[1]  = 32'h2a06b3b0;
        flash[2]  = 32'h3e37ffce;
        flash[3]  = 32'h5b5f688a;
        flash[4]  = 32'h4e42d562;
        flash[5]  = 32'hf7ea59f8;
        flash[6]  = 32'h04e6f443;
        flash[7]  = 32'hb5a0821a;
        flash[8]  = 32'h14defa68;

        // S Vector
        flash[9]  = 32'he0c52a27;
        flash[10] = 32'hf59fd2fd;
        flash[11] = 32'h971c5d4a;
        flash[12] = 32'hc97da751;
        flash[13] = 32'hd2b28568;
        flash[14] = 32'hf1169ec8;
        flash[15] = 32'hcee73616;
        flash[16] = 32'hf1e2ac0d;

        // Restored string bytes to exact original format
        flash[17] = 32'h426f6f74;
        flash[18] = 32'h6c6f6164;
        flash[19] = 32'h65725f76;
        flash[20] = 32'h312e305f;
        flash[21] = 32'h496e6974;
        flash[22] = 32'h5f536571;
        flash[23] = 32'h75656e63;
        flash[24] = 32'h652e2e2e;
    end

    task stream_word(input [31:0] d);
        @(posedge clk); #1;
        stream_data  = d;
        stream_valid = 1;
        @(posedge clk); #1;
        stream_valid = 0;
    endtask

    // =========================================================================
    // DEBUG MONITORS
    // =========================================================================

    // Monitor Top FSM
    always @(dut.state) begin
        $display("[%0t] TOP_MOST FSM: %s", $time, dut.state.name());
    end

    // Monitor SHA FSM
    always @(dut.u_sha.state) begin
        $display("[%0t] SHA512 FSM  : %s", $time, dut.u_sha.state.name());
    end

    // Monitor Key Events & Register Dump
    logic regs_dumped = 0;
    
    always @(posedge clk) begin
        if (dut.sha_intr) begin
            $display("[%0t] EVENT       : SHA512 Interrupt Asserted (Hash Complete)", $time);
        end
        if (otp_rd_en && !dut.otp_rd_en_o) begin 
            $display("[%0t] EVENT       : OTP Read Started", $time);
        end
        
        // Trigger safely based on the string name of the state
        if (!regs_dumped && dut.state.name() == "ST_ED_START") begin 
            $display("==================================================");
            $display("[%0t] PRE-VERIFICATION REGISTER DUMP:", $time);
            $display("S_REG      = %64x", dut.s_reg);
            $display("R_REG      = %64x", dut.r_reg);
            $display("PUBKEY_REG = %64x", dut.pubkey_reg);
            $display("HASH_REG   = %128x", dut.hash_reg);
            $display("==================================================");
            $display("[%0t] EVENT       : ED25519 Engine Started", $time);
            regs_dumped = 1;
        end
        
        if (verify_done && !dut.verify_done_o) begin
            $display("[%0t] EVENT       : ED25519 Engine Done | Sig Valid = %b", $time, sig_valid);
        end
    end

    // =========================================================================

    int fail = 0;

    initial begin
        $display("==================================================");
        $display("Starting Secure Boot Simulation...");
        $display("==================================================");
        
        stream_data=0; stream_valid=0; start_verify=0;
        @(posedge clk); rst_n=1;
        repeat(2) @(posedge clk);

        for (int i=0; i<=24; i++) begin
            stream_word(flash[i]);
            if (i == 0) $display("[%0t] Streamed: SHA Length = %0d", $time, flash[i]);
        end
        $display("[%0t] All Flash Data Streamed.", $time);

        // Allow time for SHA processing and OTP reads
        repeat(2000) @(posedge clk);

        @(posedge clk); #1;
        start_verify = 1;
        $display("[%0t] EVENT       : Host CPU pulsed start_verify", $time);
        @(posedge clk); #1;
        start_verify = 0;

        wait(verify_done);
        @(posedge clk);

        $display("==================================================");
        if (sig_valid) begin
            $display("FAILURE: signature_valid=1, invalid signature verified as correct");
            fail++;
        end else begin
            $display("SUCCESS: signature_valid=0, verification failed on invalid signature");
        end

        if (boot_active) begin
            $display("FAILURE: boot_active did not deassert after verify_done");
            fail++;
        end else begin
            $display("PASS: boot_active correctly deasserted after verify_done");
        end

        if (fail == 0)
            $display("SUCCESS: all functional tests passed");
        else
            $display("FAILURE: %0d test(s) failed", fail);

        $finish;
    end

    initial #2000000000 begin
        $display("FAILURE: timeout waiting for verify_done");
        $finish;
    end

endmodule