`timescale 1ns/1ps
// Testbench -- kv_cache_ctrl
// End-to-end integration checks for host control, KV read/write, capacity,
// eviction, and soft reset behavior.

module tb_kv_cache_ctrl;

    localparam TOTAL_PAGES      = 256;
    localparam PAGE_SIZE_TOKENS = 16;
    localparam HEAD_DIM         = 64;
    localparam NUM_SESSIONS     = 8;
    localparam DATA_WIDTH       = 16;
    localparam SRAM_BANKS       = 4;
    localparam KV_WIDTH         = DATA_WIDTH * HEAD_DIM;

    reg clk, rst_n;

    reg         s_axi_awvalid;
    wire        s_axi_awready;
    reg  [31:0] s_axi_awaddr;
    reg         s_axi_wvalid;
    wire        s_axi_wready;
    reg  [31:0] s_axi_wdata;
    reg  [3:0]  s_axi_wstrb;
    wire        s_axi_bvalid;
    reg         s_axi_bready;
    wire [1:0]  s_axi_bresp;
    reg         s_axi_arvalid;
    wire        s_axi_arready;
    reg  [31:0] s_axi_araddr;
    wire        s_axi_rvalid;
    reg         s_axi_rready;
    wire [31:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        irq;

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

    wire evict_valid;
    wire [7:0] evict_page_id;
    wire [2:0] evict_session_id;
    reg evict_ack;

    kv_cache_ctrl #(
        .TOTAL_PAGES(TOTAL_PAGES),
        .PAGE_SIZE_TOKENS(PAGE_SIZE_TOKENS),
        .HEAD_DIM(HEAD_DIM),
        .NUM_SESSIONS(NUM_SESSIONS),
        .DATA_WIDTH(DATA_WIDTH),
        .SRAM_BANKS(SRAM_BANKS)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .irq(irq),
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
        .evict_valid(evict_valid),
        .evict_page_id(evict_page_id),
        .evict_session_id(evict_session_id),
        .evict_ack(evict_ack)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    integer pass_cnt, fail_cnt;
    integer i, s, p;
    integer ack_count;
    integer burst_count;
    integer burst_fails;
    integer last_count;
    integer found_almost_full;
    integer found_evict;
    integer saw_deassert;
    reg [31:0] rd_tmp;
    reg [31:0] status_before;
    reg [31:0] status_after;
    reg [KV_WIDTH-1:0] exp_k;
    reg [KV_WIDTH-1:0] exp_v;
    reg [KV_WIDTH-1:0] got_k;
    reg [KV_WIDTH-1:0] got_v;
    reg got_valid;
    reg got_last;
    reg got_ack;
    reg [11:0] cap_token;
    reg [15:0] tag_tmp;

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
                v_out[idx*DATA_WIDTH +: DATA_WIDTH] = tag + 16'h6000 + idx;
            end
        end
    endtask

    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk); #1;
            s_axi_awaddr = addr;
            s_axi_wdata = data;
            s_axi_wstrb = 4'hF;
            s_axi_awvalid = 1'b1;
            s_axi_wvalid = 1'b1;
            while (!(s_axi_awready && s_axi_wready)) begin
                @(posedge clk); #1;
            end
            @(posedge clk); #1;
            s_axi_awvalid = 1'b0;
            s_axi_wvalid = 1'b0;
            s_axi_bready = 1'b1;
            while (!s_axi_bvalid) begin
                @(posedge clk); #1;
            end
            @(posedge clk); #1;
            s_axi_bready = 1'b0;
        end
    endtask

    task axi_read;
        input [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk); #1;
            s_axi_araddr = addr;
            s_axi_arvalid = 1'b1;
            while (!s_axi_arready) begin
                @(posedge clk); #1;
            end
            @(posedge clk); #1;
            s_axi_arvalid = 1'b0;
            s_axi_rready = 1'b1;
            while (!s_axi_rvalid) begin
                @(posedge clk); #1;
            end
            data = s_axi_rdata;
            @(posedge clk); #1;
            s_axi_rready = 1'b0;
        end
    endtask

    task do_write_token;
        input [2:0] sid;
        input [11:0] tok;
        input [15:0] tag;
        output ack_seen;
        integer cyc;
        begin
            make_data(tag, wr_k_data, wr_v_data);
            wr_session_id = sid;
            wr_token_pos = tok;
            ack_seen = 1'b0;
            wr_req = 1'b1;
            @(posedge clk); #1;
            wr_req = 1'b0;
            for (cyc = 0; cyc < 80; cyc = cyc + 1) begin
                @(posedge clk); #1;
                if (wr_ack)
                    ack_seen = 1'b1;
            end
        end
    endtask

    task do_read_one;
        input [2:0] sid;
        input [11:0] tok;
        output valid_seen;
        output last_seen;
        output [KV_WIDTH-1:0] k_out;
        output [KV_WIDTH-1:0] v_out;
        integer cyc;
        begin
            valid_seen = 1'b0;
            last_seen = 1'b0;
            k_out = {KV_WIDTH{1'b0}};
            v_out = {KV_WIDTH{1'b0}};
            rd_session_id = sid;
            rd_token_start = tok;
            rd_token_end = tok;
            rd_req = 1'b1;
            @(posedge clk); #1;
            rd_req = 1'b0;
            for (cyc = 0; cyc < 80; cyc = cyc + 1) begin
                @(posedge clk); #1;
                if (rd_valid) begin
                    valid_seen = 1'b1;
                    last_seen = rd_last;
                    k_out = rd_k_data;
                    v_out = rd_v_data;
                end
            end
        end
    endtask

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        ack_count = 0;
        burst_count = 0;
        burst_fails = 0;
        last_count = 0;
        found_almost_full = 0;
        found_evict = 0;
        saw_deassert = 0;
        rd_tmp = 32'd0;
        status_before = 32'd0;
        status_after = 32'd0;
        got_valid = 1'b0;
        got_last = 1'b0;
        got_ack = 1'b0;
        cap_token = 12'd0;
        tag_tmp = 16'd0;

        s_axi_awvalid = 1'b0;
        s_axi_awaddr = 32'd0;
        s_axi_wvalid = 1'b0;
        s_axi_wdata = 32'd0;
        s_axi_wstrb = 4'd0;
        s_axi_bready = 1'b0;
        s_axi_arvalid = 1'b0;
        s_axi_araddr = 32'd0;
        s_axi_rready = 1'b0;
        wr_req = 1'b0;
        wr_session_id = 3'd0;
        wr_token_pos = 12'd0;
        wr_k_data = {KV_WIDTH{1'b0}};
        wr_v_data = {KV_WIDTH{1'b0}};
        rd_req = 1'b0;
        rd_session_id = 3'd0;
        rd_token_start = 12'd0;
        rd_token_end = 12'd0;
        evict_ack = 1'b0;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        repeat (300) @(posedge clk);

        $display("");
        $display("=== Integration smoke tests ===");

        $display("");
        $display("Test 1: Enable through AXI");
        axi_write(32'h00000000, 32'h00000001);
        @(posedge clk); #1;
        check_it(irq == 1'b0, "irq is 0 at startup");

        $display("");
        $display("Test 2: Single KV write");
        do_write_token(3'd0, 12'd0, 16'h0100, got_ack);
        check_it(got_ack, "single write acknowledged");

        $display("");
        $display("Test 3: Single KV readback");
        make_data(16'h0100, exp_k, exp_v);
        do_read_one(3'd0, 12'd0, got_valid, got_last, got_k, got_v);
        check_it(got_valid, "single read valid");
        check_it(got_last, "single read last");
        check_it((got_k == exp_k) && (got_v == exp_v),
                 "single read data matches");

        $display("");
        $display("=== Multi-session end-to-end ===");

        $display("");
        $display("Test 4: Write one page each to sessions 1 and 2");
        ack_count = 0;
        for (i = 0; i < 16; i = i + 1) begin
            do_write_token(3'd1, i[11:0], 16'h1100 + i[15:0], got_ack);
            if (got_ack)
                ack_count = ack_count + 1;
        end
        for (i = 0; i < 16; i = i + 1) begin
            do_write_token(3'd2, i[11:0], 16'h2200 + i[15:0], got_ack);
            if (got_ack)
                ack_count = ack_count + 1;
        end
        check_it(ack_count == 32, "32 multi-session writes acknowledged");

        $display("");
        $display("Test 5: Read session 1 burst");
        rd_session_id = 3'd1;
        rd_token_start = 12'd0;
        rd_token_end = 12'd15;
        rd_req = 1'b1;
        @(posedge clk); #1;
        rd_req = 1'b0;
        burst_count = 0;
        burst_fails = 0;
        last_count = 0;
        for (i = 0; i < 180; i = i + 1) begin
            @(posedge clk); #1;
            if (rd_valid) begin
                tag_tmp = 16'h1100 + burst_count[15:0];
                make_data(tag_tmp, exp_k, exp_v);
                if ((rd_k_data != exp_k) || (rd_v_data != exp_v))
                    burst_fails = burst_fails + 1;
                if (rd_last) begin
                    last_count = last_count + 1;
                    if (burst_count != 15)
                        burst_fails = burst_fails + 1;
                end
                burst_count = burst_count + 1;
            end
        end
        check_it(burst_count == 16, "session 1 read returns 16 tokens");
        check_it((burst_fails == 0) && (last_count == 1),
                 "session 1 ordering and data match");

        $display("");
        $display("Test 6: Read session 2 burst");
        rd_session_id = 3'd2;
        rd_token_start = 12'd0;
        rd_token_end = 12'd15;
        rd_req = 1'b1;
        @(posedge clk); #1;
        rd_req = 1'b0;
        burst_count = 0;
        burst_fails = 0;
        last_count = 0;
        for (i = 0; i < 180; i = i + 1) begin
            @(posedge clk); #1;
            if (rd_valid) begin
                tag_tmp = 16'h2200 + burst_count[15:0];
                make_data(tag_tmp, exp_k, exp_v);
                if ((rd_k_data != exp_k) || (rd_v_data != exp_v))
                    burst_fails = burst_fails + 1;
                if (rd_last) begin
                    last_count = last_count + 1;
                    if (burst_count != 15)
                        burst_fails = burst_fails + 1;
                end
                burst_count = burst_count + 1;
            end
        end
        check_it(burst_count == 16, "session 2 read returns 16 tokens");
        check_it((burst_fails == 0) && (last_count == 1),
                 "session 2 ordering and data match");

        $display("");
        $display("=== Capacity and eviction path ===");

        $display("");
        $display("Test 7: Fill until almost_full");
        found_almost_full = 0;
        for (s = 0; s < 8; s = s + 1) begin
            for (p = 0; p < 32; p = p + 1) begin
                if (!found_almost_full) begin
                    cap_token = p * PAGE_SIZE_TOKENS;
                    do_write_token(s[2:0], cap_token,
                                   16'h3000 + (s * 32) + p, got_ack);
                    axi_read(32'h00000010, rd_tmp);
                    if (rd_tmp[16])
                        found_almost_full = 1;
                end
            end
        end
        check_it(found_almost_full, "STATUS almost_full asserted");

        $display("");
        $display("Test 8: Eviction candidate appears");
        found_evict = 0;
        for (i = 0; i < 400; i = i + 1) begin
            @(posedge clk); #1;
            if (evict_valid)
                found_evict = 1;
        end
        check_it(found_evict, "evict_valid asserts");
        check_it(evict_page_id <= 8'hFF, "evict_page_id is valid");

        $display("");
        $display("Test 9: Eviction ack frees one page");
        axi_read(32'h00000010, status_before);
        evict_ack = 1'b1;
        @(posedge clk); #1;
        evict_ack = 1'b0;
        saw_deassert = 0;
        for (i = 0; i < 40; i = i + 1) begin
            @(posedge clk); #1;
            if (!evict_valid)
                saw_deassert = 1;
        end
        axi_read(32'h00000010, status_after);
        check_it(saw_deassert, "evict_valid deasserts after ack");
        check_it(status_after[7:0] == (status_before[7:0] + 1'b1),
                 "pages_free increases by one");

        $display("");
        $display("=== Soft reset ===");

        $display("");
        $display("Test 10: Soft reset suppresses write ack");
        axi_write(32'h00000000, 32'h00000002);
        make_data(16'h7777, wr_k_data, wr_v_data);
        wr_session_id = 3'd0;
        wr_token_pos = 12'd4;
        wr_req = 1'b1;
        @(posedge clk); #1;
        wr_req = 1'b0;
        got_ack = 1'b0;
        repeat (2) begin
            @(posedge clk); #1;
            if (wr_ack)
                got_ack = 1'b1;
        end
        check_it(!got_ack, "wr_ack suppressed for two cycles");

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
        #20_000_000;
        $display("TIMEOUT -- simulation did not complete");
        $finish;
    end

endmodule
