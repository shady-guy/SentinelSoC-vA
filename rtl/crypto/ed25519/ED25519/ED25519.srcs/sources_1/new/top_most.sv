// top_most.sv — Secure boot orchestrator, passive receiver
// Receives flash stream, feeds SHA-512, reads OTP pubkey,
// loads ED25519 registers, triggers verification.

module top_most (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] stream_data_i,  // from soc_buffer
    input  logic        stream_valid_i,
    input  logic        start_verify_i, // from obi_wrapper (1-cycle pulse)
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

    // FSM
    typedef enum logic [4:0] {
        ST_IDLE, ST_SHA_CFG_LEN, ST_SHA_CFG_CTRL, ST_SHA_POLL,
        ST_RECV,
        ST_OTP_REQ, ST_OTP_LATCH,
        ST_DRAIN, ST_BLK_POLL,
        ST_WAIT_INTR, ST_READ_HASH, ST_READ_HASH_LAST,
        ST_LOAD_REGS, ST_WAIT_START, ST_ED_START, ST_ED_WAIT, ST_DONE
    } state_t;
    state_t state;

    // Datapath
    logic [31:0]  sha_len_reg;
    logic [255:0] s_reg, r_reg, pubkey_reg;
    logic [511:0] hash_reg;
    logic [31:0]  word_cnt;      // global stream counter
    logic [31:0]  sha_fed;       // total words written to SHA data range
    logic [4:0]   blk_ptr;       // position in current 32-word SHA block
    logic [2:0]   otp_idx;
    logic [3:0]   hash_idx;
    logic [4:0]   load_idx;

    // 16-word staging FIFO
    logic [31:0] stage [0:15];
    logic [3:0]  s_wr, s_rd, s_cnt;

    logic otp_done, start_latch, boot_q;

    assign boot_active_o = boot_q;
    assign otp_addr_o    = otp_idx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            word_cnt    <= 0; sha_fed <= 0; blk_ptr <= 0;
            otp_idx     <= 0; hash_idx <= 0; load_idx <= 0;
            s_wr<=0; s_rd<=0; s_cnt<=0;
            otp_done<=0; start_latch<=0; boot_q<=1;
            sha_len_reg<=0; s_reg<=0; r_reg<=0; pubkey_reg<=0; hash_reg<=0;
            sha_addr<=0; sha_wen<=0; sha_wdata<=0;
            ed_start<=0; ed_ext_we<=0; ed_dest<=0; ed_dsel<=0; ed_din<=0;
            otp_rd_en_o<=0;
        end else begin
            // defaults
            sha_wen <= 0; ed_start <= 0; otp_rd_en_o <= 0;

            if (start_verify_i) start_latch <= 1;
            if (ed_done)        boot_q      <= 0;

            case (state)

                ST_IDLE: begin
                    if (stream_valid_i) begin
                        sha_len_reg <= stream_data_i;
                        word_cnt    <= 1;
                        state       <= ST_SHA_CFG_LEN;
                    end
                end

                // Configure SHA: length then start+init
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
                    if (sha_rdata[0]) state <= ST_RECV;
                end

                // Main receive
                ST_RECV: begin
                    // All SHA data sent — go wait for hash
                    if (sha_fed == sha_len_reg) begin
                        state <= ST_WAIT_INTR;

                    // After word 16, trigger OTP read
                    end else if (word_cnt == 17 && !otp_done) begin
                        otp_idx <= 0;
                        state   <= ST_OTP_REQ;

                    // Drain staging when OTP done and staging has data
                    end else if (otp_done && s_cnt > 0) begin
                        state <= ST_DRAIN;

                    end else if (stream_valid_i) begin
                        word_cnt <= word_cnt + 1;

                        if (word_cnt >= 1 && word_cnt <= 8) begin
                            // S words
                            s_reg <= {stream_data_i, s_reg[255:32]};
                        end
                        else if (word_cnt >= 9 && word_cnt <= 16) begin
                            // R words — also feed SHA
                            r_reg       <= {stream_data_i, r_reg[255:32]};
                            sha_addr    <= 6'(word_cnt - 9);
                            sha_wdata   <= stream_data_i;
                            sha_wen     <= 1;
                            sha_fed     <= sha_fed + 1;
                            blk_ptr     <= blk_ptr + 1;
                        end
                        else if (word_cnt >= 17) begin
                            if (!otp_done) begin
                                // Stage it
                                stage[s_wr] <= stream_data_i;
                                s_wr <= s_wr + 1;
                                s_cnt <= s_cnt + 1;
                            end else begin
                                // Feed SHA directly
                                sha_addr  <= 6'(blk_ptr);
                                sha_wdata <= stream_data_i;
                                sha_wen   <= 1;
                                sha_fed   <= sha_fed + 1;
                                blk_ptr   <= blk_ptr + 1;
                                if (blk_ptr == 31) begin
                                    blk_ptr <= 0;
                                    state   <= ST_BLK_POLL;
                                end
                            end
                        end
                    end
                end

                // OTP: assert rd_en, then latch next cycle
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
                        otp_done <= 1;
                        if (blk_ptr == 31) begin
                            blk_ptr <= 0; state <= ST_BLK_POLL;
                        end else
                            state <= (s_cnt > 0) ? ST_DRAIN : ST_RECV;
                    end else begin
                        otp_idx <= otp_idx + 1;
                        state   <= ST_OTP_REQ;
                    end
                end

                // Drain staging FIFO into SHA
                ST_DRAIN: begin
                    if (s_cnt > 0 && sha_fed < sha_len_reg) begin
                        sha_addr  <= 6'(blk_ptr);
                        sha_wdata <= stage[s_rd];
                        sha_wen   <= 1;
                        sha_fed   <= sha_fed + 1;
                        blk_ptr   <= blk_ptr + 1;
                        s_rd      <= s_rd + 1;
                        s_cnt     <= s_cnt - 1;
                        if (blk_ptr == 31) begin
                            blk_ptr <= 0; state <= ST_BLK_POLL;
                        end
                    end else begin
                        state <= (sha_fed == sha_len_reg) ? ST_WAIT_INTR : ST_RECV;
                    end
                end

                // Poll SHA ready after full block
                ST_BLK_POLL: begin
                    sha_addr <= 6'h21;
                    if (sha_rdata[0]) begin
                        if (sha_fed == sha_len_reg)
                            state <= ST_WAIT_INTR;
                        else
                            state <= (s_cnt > 0) ? ST_DRAIN : ST_RECV;
                    end
                end

                // Wait for SHA done interrupt
                ST_WAIT_INTR: begin
                    if (sha_intr) begin
                        hash_idx <= 0;
                        sha_addr <= 6'h22;
                        state    <= ST_READ_HASH;
                    end
                end

                // Read 16 hash words (0x22-0x31)
                // rdata_o is combinational from addr_i, so:
                // cycle 0: set addr=0x22, rdata not yet latched
                // cycle 1: latch rdata[0x22], set addr=0x23 ...
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

                // Load 17 ED25519 registers, one per cycle
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
                    if (load_idx == 16) begin
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
                ST_DONE:     ; // single-use per reset

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule