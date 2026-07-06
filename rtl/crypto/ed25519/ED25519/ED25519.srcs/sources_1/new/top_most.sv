// top_most.sv — Secure boot orchestrator, passive receiver
// Receives flash stream, feeds SHA-512, reads OTP pubkey,
// loads ED25519 registers, triggers verification.

module top_most (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] stream_data_i,  
    input  logic        stream_valid_i,
    input  logic        start_verify_i, 
    output logic [2:0]  otp_addr_o,
    output logic        otp_rd_en_o,
    input  logic [31:0] otp_data_i,
    output logic        boot_active_o,
    output logic        verify_done_o,
    output logic        signature_valid_o
);

    // Ed25519 constants
    localparam logic [255:0] CONST_ZERO = 256'd0;
    localparam logic [255:0] CONST_ONE  = 256'd1;
    localparam logic [255:0] CURVE_D  = 256'h52036cee2b6ffe738cc740797779e89800700a4d4141d8ab75eb4dca135978a3;
    localparam logic [255:0] CURVE_2D = 256'h2406d9dc56dffce7198e80f2eef3d13000e0149a8283b156ebd69b9426b2f159;
    localparam logic [255:0] SQRT_M1  = 256'h2b8324804fc1df0b2b4d00993dfbd7a72f431806ad2fe478c4ee1b274a0ea0b0;
    localparam logic [255:0] G_X      = 256'h216936d3cd6e53fec0a4e231fdd6dc5c692cc7609525a7b2c9562d608f25d51a;
    localparam logic [255:0] G_Y      = 256'h6666666666666666666666666666666666666666666666666666666666666658;
    localparam logic [255:0] G_Z      = 256'd1;
    localparam logic [255:0] G_T      = 256'h67875f0fd78b766566ea4e8e64abe37d20f09f80775152f56dde8ab3a5b7dda3;
    localparam logic [255:0] MU_HI    = 256'h000000000000000000000000000000000000000000000000000000000000000f;
    localparam logic [255:0] MU_LO    = 256'hffffffffffffffffffffffffffffffeb2106215d086329a7ed9ce5a30a2c131b;
    localparam logic [255:0] CURVE_L  = 256'h1000000000000000000000000000000014def9dea2f79cd65812631a5cf5d3ed;

    // SHA-512 interface
    logic [5:0]  sha_addr;
    logic        sha_wen;
    logic [31:0] sha_wdata, sha_rdata;
    logic        sha_intr;

    sha512_top u_sha (
        .clk(clk), .rst_n(rst_n),
        .addr_i(sha_addr), .wr_en_i(sha_wen),
        .wdata_i(sha_wdata), .rdata_o(sha_rdata), .intr_o(sha_intr)
    );

    // ED25519 interface
    logic        ed_start, ed_done, ed_valid, ed_ext_we;
    logic [4:0]  ed_dest;
    logic [1:0]  ed_dsel;
    logic [255:0] ed_din;

    top_ed25519 u_ed (
        .clk(clk), .rst_n(rst_n),
        .start_verify(ed_start),
        .ext_data_1(ed_din), .ext_data_2(256'd0), .otp_data(256'd0),
        .data_sel(ed_dsel), .ext_we(ed_ext_we), .ext_dest_sel(ed_dest),
        .verify_done(ed_done), .signature_valid(ed_valid)
    );

    assign verify_done_o     = ed_done;
    assign signature_valid_o = ed_valid;

    // --- Front-End Synchronous FIFO ---
    logic [31:0] fifo_data [0:63];
    logic [5:0]  fifo_wr_ptr, fifo_rd_ptr;
    logic [6:0]  fifo_count;
    logic        fifo_empty, fifo_full, fifo_pop;
    logic [31:0] fifo_dout;

    assign fifo_empty = (fifo_count == 0);
    assign fifo_full  = (fifo_count == 64);
    assign fifo_dout  = fifo_data[fifo_rd_ptr];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wr_ptr <= 0;
            fifo_rd_ptr <= 0;
            fifo_count  <= 0;
        end else begin
            // Write
            if (stream_valid_i && !fifo_full) begin
                fifo_data[fifo_wr_ptr] <= stream_data_i;
                fifo_wr_ptr <= fifo_wr_ptr + 1;
            end
            
            // Count management
            if (stream_valid_i && !fifo_full && fifo_pop && !fifo_empty)
                fifo_count <= fifo_count;
            else if (stream_valid_i && !fifo_full)
                fifo_count <= fifo_count + 1;
            else if (fifo_pop && !fifo_empty)
                fifo_count <= fifo_count - 1;

            // Read pointer
            if (fifo_pop && !fifo_empty) begin
                fifo_rd_ptr <= fifo_rd_ptr + 1;
            end
        end
    end

    // FSM States
    typedef enum logic [4:0] {
        ST_IDLE, ST_SHA_CFG_LEN, ST_SHA_CFG_CTRL, ST_SHA_POLL,
        ST_RECV_S, ST_RECV_R,
        ST_OTP_REQ, ST_OTP_LATCH, ST_BLK_POLL_OTP,
        ST_RECV_MSG, ST_BLK_POLL,
        ST_WAIT_INTR, ST_READ_HASH, ST_READ_HASH_LAST,
        ST_LOAD_REGS, ST_WAIT_START, ST_ED_START, ST_ED_WAIT, ST_DONE
    } state_t;
    state_t state;

    // Combinatorial pop evaluation for 1-cycle latency stream processing
    always_comb begin
        fifo_pop = 1'b0;
        if (!fifo_empty) begin
            if (state == ST_IDLE || state == ST_RECV_S || state == ST_RECV_R || state == ST_RECV_MSG)
                fifo_pop = 1'b1;
        end
    end

    // Datapath
    logic [31:0]  sha_len_reg;
    logic [255:0] s_reg, r_reg, pubkey_reg;
    logic [511:0] hash_reg;
    logic [31:0]  word_cnt;      
    logic [31:0]  sha_fed;       
    logic [4:0]   blk_ptr;       
    logic [2:0]   otp_idx;
    logic [3:0]   hash_idx;
    logic [4:0]   load_idx;

    logic start_latch, boot_q;

    assign boot_active_o = boot_q;
    assign otp_addr_o    = otp_idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            word_cnt    <= 0; sha_fed <= 0; blk_ptr <= 0;
            otp_idx     <= 0; hash_idx <= 0; load_idx <= 0;
            start_latch <= 0; boot_q <= 1;
            sha_len_reg <= 0; s_reg <= 0; r_reg <= 0; pubkey_reg <= 0; hash_reg <= 0;
            sha_addr    <= 0; sha_wen <= 0; sha_wdata <= 0;
            ed_start    <= 0; ed_ext_we <= 0; ed_dest <= 0; ed_dsel <= 0; ed_din <= 0;
            otp_rd_en_o <= 0;
        end else begin
            // Defaults
            sha_wen <= 0; ed_start <= 0; otp_rd_en_o <= 0;

            if (start_verify_i) start_latch <= 1;
            if (ed_done)        boot_q      <= 0;

            case (state)

                ST_IDLE: begin
                    if (!fifo_empty) begin
                        sha_len_reg <= fifo_dout;
                        state       <= ST_SHA_CFG_LEN;
                    end
                end

                // Configure SHA length then start
                ST_SHA_CFG_LEN: begin
                    sha_addr<=6'h32; sha_wdata<=sha_len_reg; sha_wen<=1;
                    state <= ST_SHA_CFG_CTRL;
                end
                ST_SHA_CFG_CTRL: begin
                    sha_addr<=6'h20; sha_wdata<=32'h03; sha_wen<=1;
                    state <= ST_SHA_POLL;
                end
                ST_SHA_POLL: begin
                    sha_addr <= 6'h21;
                    if (sha_rdata[0]) begin
                        word_cnt <= 0;
                        state <= ST_RECV_S;
                    end
                end

                // Construct S Register (MSB First)
                ST_RECV_S: begin
                    if (!fifo_empty) begin
                        s_reg <= {fifo_dout, s_reg[255:32]}; 
                        word_cnt <= word_cnt + 1;
                        if (word_cnt == 7) state <= ST_RECV_R; 
                    end
                end

                // Construct R Register and feed to SHA
                ST_RECV_R: begin
                    if (!fifo_empty) begin
                        r_reg       <= {fifo_dout, r_reg[255:32]};
                        sha_addr    <= 6'(blk_ptr);
                        sha_wdata   <= fifo_dout;
                        sha_wen     <= 1;
                        sha_fed     <= sha_fed + 1;
                        blk_ptr     <= blk_ptr + 1;
                        word_cnt    <= word_cnt + 1;
                        
                        if (word_cnt == 15) state <= ST_OTP_REQ;
                    end
                end

                // Fetch Public Key from OTP
                ST_OTP_REQ: begin
                    otp_rd_en_o <= 1;
                    state       <= ST_OTP_LATCH;
                end
                ST_OTP_LATCH: begin
                    pubkey_reg <= {otp_data_i, pubkey_reg[255:32]};
                    sha_addr   <= 6'(blk_ptr);
                    sha_wdata  <= otp_data_i;
                    sha_wen    <= 1;
                    sha_fed    <= sha_fed + 1;
                    blk_ptr    <= blk_ptr + 1;
                    
                    if (otp_idx == 7) begin
                        if (sha_fed + 1 == sha_len_reg) begin
                            state <= ST_WAIT_INTR;
                        end else if (blk_ptr == 31) begin
                            blk_ptr <= 0; state <= ST_BLK_POLL;
                        end else begin
                            state <= ST_RECV_MSG;
                        end
                    end else begin
                        otp_idx <= otp_idx + 1;
                        if (blk_ptr == 31) begin
                            blk_ptr <= 0; state <= ST_BLK_POLL_OTP;
                        end else begin
                            state <= ST_OTP_REQ;
                        end
                    end
                end

                // Poll SHA during OTP fetch if block boundary crossed
                ST_BLK_POLL_OTP: begin
                    sha_addr <= 6'h21;
                    if (sha_rdata[0]) state <= ST_OTP_REQ;
                end

                // Feed remaining message payload directly to SHA
                ST_RECV_MSG: begin
                    if (!fifo_empty) begin
                        sha_addr  <= 6'(blk_ptr);
                        sha_wdata <= fifo_dout;
                        sha_wen   <= 1;
                        sha_fed   <= sha_fed + 1;
                        blk_ptr   <= blk_ptr + 1;
                        
                        if (sha_fed + 1 == sha_len_reg) begin
                            state <= ST_WAIT_INTR;
                        end else if (blk_ptr == 31) begin
                            blk_ptr <= 0; state <= ST_BLK_POLL;
                        end
                    end
                end

                // Generic block boundary poll
                ST_BLK_POLL: begin
                    sha_addr <= 6'h21;
                    if (sha_rdata[0]) state <= ST_RECV_MSG;
                end

                // Wait for SHA Done
                ST_WAIT_INTR: begin
                    if (sha_intr) begin
                        hash_idx <= 0;
                        sha_addr <= 6'h22;
                        state    <= ST_READ_HASH;
                    end
                end

                // Extract 512-bit Hash (MSB First)
                ST_READ_HASH: begin
                    hash_reg <= {sha_rdata, hash_reg[511:32]};
                    hash_idx <= hash_idx + 1;
                    if (hash_idx == 14) begin
                        sha_addr <= 6'h31;
                        state    <= ST_READ_HASH_LAST;
                    end else begin
                        sha_addr <= 6'h22 + {2'b0, hash_idx + 1};
                    end
                end
                ST_READ_HASH_LAST: begin
                    hash_reg <= {sha_rdata, hash_reg[511:32]};
                    load_idx <= 0;
                    state    <= ST_LOAD_REGS;
                end

                // Load ED25519 Math Registers
                ST_LOAD_REGS: begin
                    ed_ext_we <= 1;
                    ed_dsel   <= 2'b01;
                    load_idx  <= load_idx + 1;
                    
                    case (load_idx)
                        0:  begin ed_dest<=24; ed_din<=CONST_ZERO;        end
                        1:  begin ed_dest<=25; ed_din<=CONST_ONE;         end
                        2:  begin ed_dest<=26; ed_din<=CURVE_D;           end
                        3:  begin ed_dest<=27; ed_din<=CURVE_2D;          end
                        4:  begin ed_dest<=28; ed_din<=SQRT_M1;           end
                        5:  begin ed_dest<=4;  ed_din<=G_X;               end
                        6:  begin ed_dest<=5;  ed_din<=G_Y;               end
                        7:  begin ed_dest<=6;  ed_din<=G_Z;               end
                        8:  begin ed_dest<=7;  ed_din<=G_T;               end
                        9:  begin ed_dest<=10; ed_din<=MU_HI;             end
                        10: begin ed_dest<=11; ed_din<=CURVE_L;           end
                        11: begin ed_dest<=12; ed_din<=MU_LO;             end
                        12: begin ed_dest<=23; ed_din<=s_reg;             end
                        13: begin ed_dest<=20; ed_din<=r_reg;             end
                        14: begin ed_dest<=21; ed_din<=pubkey_reg;        end
                        15: begin ed_dest<=8;  ed_din<=hash_reg[255:0];   end
                        16: begin ed_dest<=9;  ed_din<=hash_reg[511:256]; end
                        default: ;
                    endcase
                    
                    if (load_idx == 17) begin
                        ed_ext_we <= 0;
                        state     <= ST_WAIT_START;
                    end
                end

                ST_WAIT_START: begin
                    ed_dsel <= 2'b00;
                    if (start_latch || start_verify_i) begin
                        start_latch <= 0;
                        state       <= ST_ED_START;
                    end
                end

                ST_ED_START: begin ed_start<=1; state<=ST_ED_WAIT; end
                ST_ED_WAIT:  begin if (ed_done) state<=ST_DONE;    end
                ST_DONE:     ; 

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule