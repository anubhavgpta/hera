`timescale 1ns/1ps
// Testbench -- rw_engine
// Covers single-token access, burst access, page crossing, session isolation,
// and rd_busy behavior using stub block table and SRAM models.

module tb_rw_engine;

    localparam NUM_SESSIONS     = 8;
    localparam TOTAL_PAGES      = 256;
    localparam PAGE_SIZE_TOKENS = 16;
    localparam HEAD_DIM         = 64;
    localparam DATA_WIDTH       = 16;
    localparam SRAM_BANKS       = 4;
    localparam KV_WIDTH         = DATA_WIDTH * HEAD_DIM;
    localparam SRAM_WIDTH       = KV_WIDTH * 2;

    reg clk, rst_n;

    reg wr_req;
    reg [2:0] wr_session_id;
    reg [11:0] wr_token_pos;
    reg [KV_WIDTH-1:0] wr_k_data;
    reg [KV_WIDTH-1:0] wr_v_data;
    wire wr_ack;

    reg rd_req;
    reg [2:0] rd_session_id;
    reg [11:0] rd_token_start;
    reg [11:0] rd_token_end;
    wire [KV_WIDTH-1:0] rd_k_data;
    wire [KV_WIDTH-1:0] rd_v_data;
    wire rd_valid;
    wire rd_last;
    wire rd_busy;

    wire [2:0] bt_rd_session;
    wire [4:0] bt_rd_logical_page;
    reg  [7:0] bt_rd_physical_page;
    reg        bt_rd_valid;

    wire [SRAM_BANKS-1:0] sram_ce;
    wire [SRAM_BANKS-1:0] sram_we;
    wire [7:0] sram_addr [SRAM_BANKS-1:0];
    wire [SRAM_WIDTH-1:0] sram_wdata;
    reg  [SRAM_WIDTH-1:0] sram_rdata [SRAM_BANKS-1:0];

    rw_engine #(
        .NUM_SESSIONS(NUM_SESSIONS),
        .TOTAL_PAGES(TOTAL_PAGES),
        .PAGE_SIZE_TOKENS(PAGE_SIZE_TOKENS),
        .HEAD_DIM(HEAD_DIM),
        .DATA_WIDTH(DATA_WIDTH),
        .SRAM_BANKS(SRAM_BANKS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .wr_req(wr_req),
        .wr_session_id(wr_session_id),
        .wr_token_pos(wr_token_pos),
        .wr_k_data(wr_k_data),
        .wr_v_data(wr_v_data),
        .wr_ack(wr_ack),
        .rd_req(rd_req),
        .rd_session_id(rd_session_id),
        .rd_token_start(rd_token_start),
        .rd_token_end(rd_token_end),
        .rd_k_data(rd_k_data),
        .rd_v_data(rd_v_data),
        .rd_valid(rd_valid),
        .rd_last(rd_last),
        .rd_busy(rd_busy),
        .bt_rd_session(bt_rd_session),
        .bt_rd_logical_page(bt_rd_logical_page),
        .bt_rd_physical_page(bt_rd_physical_page),
        .bt_rd_valid(bt_rd_valid),
        .sram_ce(sram_ce),
        .sram_we(sram_we),
        .sram_addr(sram_addr),
        .sram_wdata(sram_wdata),
        .sram_rdata(sram_rdata)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    reg [7:0] block_map [0:NUM_SESSIONS-1][0:31];
    reg [SRAM_WIDTH-1:0] sram_mem0 [0:255];
    reg [SRAM_WIDTH-1:0] sram_mem1 [0:255];
    reg [SRAM_WIDTH-1:0] sram_mem2 [0:255];
    reg [SRAM_WIDTH-1:0] sram_mem3 [0:255];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bt_rd_physical_page <= 8'd0;
            bt_rd_valid <= 1'b0;
        end else begin
            bt_rd_physical_page <= block_map[bt_rd_session][bt_rd_logical_page];
            bt_rd_valid <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (sram_ce[0]) begin
            if (sram_we[0])
                sram_mem0[sram_addr[0]] <= sram_wdata;
            sram_rdata[0] <= sram_mem0[sram_addr[0]];
        end
        if (sram_ce[1]) begin
            if (sram_we[1])
                sram_mem1[sram_addr[1]] <= sram_wdata;
            sram_rdata[1] <= sram_mem1[sram_addr[1]];
        end
        if (sram_ce[2]) begin
            if (sram_we[2])
                sram_mem2[sram_addr[2]] <= sram_wdata;
            sram_rdata[2] <= sram_mem2[sram_addr[2]];
        end
        if (sram_ce[3]) begin
            if (sram_we[3])
                sram_mem3[sram_addr[3]] <= sram_wdata;
            sram_rdata[3] <= sram_mem3[sram_addr[3]];
        end
    end

    integer pass_cnt, fail_cnt;
    integer i, s, p;

    task check_it;
        input cond;
        input [255:0] msg;
        begin
            if (cond) begin
                $display("  PASS: %s", msg);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("  FAIL: %s", msg);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    task make_data;
        input [15:0] tag;
        output [KV_WIDTH-1:0] k_out;
        output [KV_WIDTH-1:0] v_out;
        integer idx;
        begin
            for (idx = 0; idx < HEAD_DIM; idx = idx + 1) begin
                k_out[idx*DATA_WIDTH +: DATA_WIDTH] = tag + idx;
                v_out[idx*DATA_WIDTH +: DATA_WIDTH] = tag + 16'h4000 + idx;
            end
        end
    endtask

    task do_write;
        input [2:0] sid;
        input [11:0] tok;
        input [15:0] tag;
        output got_ack;
        reg [KV_WIDTH-1:0] k_tmp;
        reg [KV_WIDTH-1:0] v_tmp;
        integer cyc;
        begin
            make_data(tag, k_tmp, v_tmp);
            got_ack = 1'b0;
            wr_session_id = sid;
            wr_token_pos = tok;
            wr_k_data = k_tmp;
            wr_v_data = v_tmp;
            wr_req = 1'b1;
            @(posedge clk); #1;
            wr_req = 1'b0;
            for (cyc = 0; cyc < 8; cyc = cyc + 1) begin
                @(posedge clk); #1;
                if (wr_ack)
                    got_ack = 1'b1;
            end
        end
    endtask

    task do_read_one;
        input [2:0] sid;
        input [11:0] tok;
        output got_valid;
        output got_last;
        output [KV_WIDTH-1:0] k_out;
        output [KV_WIDTH-1:0] v_out;
        integer cyc;
        begin
            got_valid = 1'b0;
            got_last = 1'b0;
            k_out = {KV_WIDTH{1'b0}};
            v_out = {KV_WIDTH{1'b0}};
            rd_session_id = sid;
            rd_token_start = tok;
            rd_token_end = tok;
            rd_req = 1'b1;
            @(posedge clk); #1;
            rd_req = 1'b0;
            for (cyc = 0; cyc < 12; cyc = cyc + 1) begin
                @(posedge clk); #1;
                if (rd_valid) begin
                    got_valid = 1'b1;
                    got_last = rd_last;
                    k_out = rd_k_data;
                    v_out = rd_v_data;
                end
            end
        end
    endtask

    reg ack_tmp;
    reg valid_tmp;
    reg last_tmp;
    reg [KV_WIDTH-1:0] exp_k;
    reg [KV_WIDTH-1:0] exp_v;
    reg [KV_WIDTH-1:0] got_k;
    reg [KV_WIDTH-1:0] got_v;
    reg [15:0] tag_tmp;
    integer burst_valids;
    integer burst_fails;
    integer last_count;

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        wr_req = 1'b0;
        wr_session_id = 3'd0;
        wr_token_pos = 12'd0;
        wr_k_data = {KV_WIDTH{1'b0}};
        wr_v_data = {KV_WIDTH{1'b0}};
        rd_req = 1'b0;
        rd_session_id = 3'd0;
        rd_token_start = 12'd0;
        rd_token_end = 12'd0;
        ack_tmp = 1'b0;
        valid_tmp = 1'b0;
        last_tmp = 1'b0;
        burst_valids = 0;
        burst_fails = 0;
        last_count = 0;

        for (s = 0; s < NUM_SESSIONS; s = s + 1)
            for (p = 0; p < 32; p = p + 1)
                block_map[s][p] = (s * 8) + p;

        for (i = 0; i < 256; i = i + 1) begin
            sram_mem0[i] = {SRAM_WIDTH{1'b0}};
            sram_mem1[i] = {SRAM_WIDTH{1'b0}};
            sram_mem2[i] = {SRAM_WIDTH{1'b0}};
            sram_mem3[i] = {SRAM_WIDTH{1'b0}};
        end
        sram_rdata[0] = {SRAM_WIDTH{1'b0}};
        sram_rdata[1] = {SRAM_WIDTH{1'b0}};
        sram_rdata[2] = {SRAM_WIDTH{1'b0}};
        sram_rdata[3] = {SRAM_WIDTH{1'b0}};

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;

        $display("");
        $display("=== Test 1: Single token write ===");
        do_write(3'd0, 12'd0, 16'h0100, ack_tmp);
        check_it(ack_tmp, "wr_ack fires for single write");

        $display("");
        $display("=== Test 2: Single token read ===");
        make_data(16'h0100, exp_k, exp_v);
        do_read_one(3'd0, 12'd0, valid_tmp, last_tmp, got_k, got_v);
        check_it(valid_tmp, "rd_valid fires for single read");
        check_it(last_tmp, "rd_last fires for single read");
        check_it((got_k == exp_k) && (got_v == exp_v), "single read data matches");

        $display("");
        $display("=== Test 3: Sequential burst write ===");
        burst_fails = 0;
        for (i = 0; i < 32; i = i + 1) begin
            do_write(3'd1, i[11:0], 16'h0200 + i[15:0], ack_tmp);
            if (!ack_tmp)
                burst_fails = burst_fails + 1;
        end
        check_it(burst_fails == 0, "32 write acknowledgements received");

        $display("");
        $display("=== Test 4: Sequential burst read ===");
        rd_session_id = 3'd1;
        rd_token_start = 12'd0;
        rd_token_end = 12'd31;
        rd_req = 1'b1;
        @(posedge clk); #1;
        rd_req = 1'b0;
        burst_valids = 0;
        burst_fails = 0;
        last_count = 0;
        for (i = 0; i < 220; i = i + 1) begin
            @(posedge clk); #1;
            if (rd_valid) begin
                tag_tmp = 16'h0200 + burst_valids[15:0];
                make_data(tag_tmp, exp_k, exp_v);
                if ((rd_k_data != exp_k) || (rd_v_data != exp_v))
                    burst_fails = burst_fails + 1;
                if (rd_last) begin
                    last_count = last_count + 1;
                    if (burst_valids != 31)
                        burst_fails = burst_fails + 1;
                end
                burst_valids = burst_valids + 1;
            end
        end
        check_it(burst_valids == 32, "32 read valid pulses received");
        check_it(burst_fails == 0, "burst read ordering and data match");
        check_it(last_count == 1, "rd_last only on token 31");

        $display("");
        $display("=== Test 5: Page boundary crossing ===");
        do_write(3'd2, 12'd15, 16'h030f, ack_tmp);
        do_write(3'd2, 12'd16, 16'h0310, ack_tmp);
        rd_session_id = 3'd2;
        rd_token_start = 12'd15;
        rd_token_end = 12'd16;
        rd_req = 1'b1;
        @(posedge clk); #1;
        rd_req = 1'b0;
        burst_valids = 0;
        burst_fails = 0;
        last_count = 0;
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk); #1;
            if (rd_valid) begin
                if (burst_valids == 0)
                    tag_tmp = 16'h030f;
                else
                    tag_tmp = 16'h0310;
                make_data(tag_tmp, exp_k, exp_v);
                if ((rd_k_data != exp_k) || (rd_v_data != exp_v))
                    burst_fails = burst_fails + 1;
                if (rd_last) begin
                    last_count = last_count + 1;
                    if (burst_valids != 1)
                        burst_fails = burst_fails + 1;
                end
                burst_valids = burst_valids + 1;
            end
        end
        check_it(burst_valids == 2, "two boundary tokens returned");
        check_it(burst_fails == 0, "boundary data matches");
        check_it(last_count == 1, "boundary rd_last on token 16");

        $display("");
        $display("=== Test 6: Multi-session isolation ===");
        do_write(3'd3, 12'd7, 16'h0403, ack_tmp);
        do_write(3'd4, 12'd7, 16'h0404, ack_tmp);
        make_data(16'h0403, exp_k, exp_v);
        do_read_one(3'd3, 12'd7, valid_tmp, last_tmp, got_k, got_v);
        check_it(valid_tmp && last_tmp && (got_k == exp_k) && (got_v == exp_v),
                 "session 3 data isolated");
        make_data(16'h0404, exp_k, exp_v);
        do_read_one(3'd4, 12'd7, valid_tmp, last_tmp, got_k, got_v);
        check_it(valid_tmp && last_tmp && (got_k == exp_k) && (got_v == exp_v),
                 "session 4 data isolated");

        $display("");
        $display("=== Test 7: rd_busy signal ===");
        rd_session_id = 3'd1;
        rd_token_start = 12'd0;
        rd_token_end = 12'd3;
        rd_req = 1'b1;
        @(posedge clk); #1;
        check_it(rd_busy, "rd_busy asserts after rd_req");
        rd_req = 1'b0;
        last_tmp = 1'b0;
        for (i = 0; i < 60; i = i + 1) begin
            @(posedge clk); #1;
            if (rd_valid && rd_last)
                last_tmp = 1'b1;
        end
        check_it(last_tmp, "rd_last observed for busy test");
        check_it(!rd_busy, "rd_busy deasserts after rd_last");

        $display("");
        $display("============================================");
        $display("Checks passed : %0d", pass_cnt);
        $display("Checks failed : %0d", fail_cnt);
        if (fail_cnt == 0)
            $display("OVERALL RESULT: PASS");
        else
            $display("OVERALL RESULT: FAIL");
        $display("============================================");
        $display("");
        $finish;
    end

    initial begin
        #5_000_000;
        $display("TIMEOUT -- simulation did not complete");
        $finish;
    end

endmodule
