`timescale 1ns/1ps
// Testbench -- prefetch_ctrl and eviction_engine
// Combined self-checking bench with independent section summaries.

module tb_prefetch_eviction;

    localparam NUM_SESSIONS     = 8;
    localparam PAGE_SIZE_TOKENS = 16;
    localparam TOTAL_PAGES      = 256;

    reg clk, rst_n;

    // Prefetch DUT signals
    reg  [2:0]  obs_session_id;
    reg  [11:0] obs_token_pos;
    reg         obs_rd_req;
    wire [2:0]  pf_session_id;
    wire [4:0]  pf_logical_page;
    wire        pf_req;
    reg         pf_ack;
    wire        pf_buf_valid [1:0];
    wire [4:0]  pf_buf_page  [1:0];
    wire [2:0]  pf_buf_sess  [1:0];

    // Eviction DUT signals
    reg         almost_full;
    reg         lru_update_en;
    reg  [7:0]  lru_update_page;
    wire        evict_valid;
    wire [7:0]  evict_page_id;
    wire [2:0]  evict_session_id;
    reg         evict_ack;
    wire        free_req;
    wire [7:0]  free_page_id;
    reg  [2:0]  page_session_map [255:0];

    prefetch_ctrl #(
        .NUM_SESSIONS(NUM_SESSIONS),
        .PAGE_SIZE_TOKENS(PAGE_SIZE_TOKENS)
    ) u_prefetch (
        .clk(clk),
        .rst_n(rst_n),
        .obs_session_id(obs_session_id),
        .obs_token_pos(obs_token_pos),
        .obs_rd_req(obs_rd_req),
        .pf_session_id(pf_session_id),
        .pf_logical_page(pf_logical_page),
        .pf_req(pf_req),
        .pf_ack(pf_ack),
        .pf_buf_valid(pf_buf_valid),
        .pf_buf_page(pf_buf_page),
        .pf_buf_sess(pf_buf_sess)
    );

    eviction_engine #(
        .NUM_SESSIONS(NUM_SESSIONS),
        .TOTAL_PAGES(TOTAL_PAGES)
    ) u_evict (
        .clk(clk),
        .rst_n(rst_n),
        .almost_full(almost_full),
        .lru_update_en(lru_update_en),
        .lru_update_page(lru_update_page),
        .evict_valid(evict_valid),
        .evict_page_id(evict_page_id),
        .evict_session_id(evict_session_id),
        .evict_ack(evict_ack),
        .free_req(free_req),
        .free_page_id(free_page_id),
        .page_session_map(page_session_map)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    integer pass_a, fail_a;
    integer pass_b, fail_b;
    integer i;
    reg saw_pf;
    reg [4:0] saw_pf_page;
    reg [2:0] saw_pf_sess;
    reg saw_free;

    task check_a;
        input cond;
        input [255:0] msg;
        begin
            if (cond) begin
                $display("  PASS: %s", msg);
                pass_a = pass_a + 1;
            end else begin
                $display("  FAIL: %s", msg);
                fail_a = fail_a + 1;
            end
        end
    endtask

    task check_b;
        input cond;
        input [255:0] msg;
        begin
            if (cond) begin
                $display("  PASS: %s", msg);
                pass_b = pass_b + 1;
            end else begin
                $display("  FAIL: %s", msg);
                fail_b = fail_b + 1;
            end
        end
    endtask

    task obs_read;
        input [2:0] sid;
        input [11:0] tok;
        output pf_seen;
        output [2:0] pf_sess_seen;
        output [4:0] pf_page_seen;
        begin
            pf_seen = 1'b0;
            pf_sess_seen = 3'd0;
            pf_page_seen = 5'd0;
            obs_session_id = sid;
            obs_token_pos = tok;
            obs_rd_req = 1'b1;
            @(posedge clk); #1;
            if (pf_req) begin
                pf_seen = 1'b1;
                pf_sess_seen = pf_session_id;
                pf_page_seen = pf_logical_page;
            end
            obs_rd_req = 1'b0;
            @(posedge clk); #1;
        end
    endtask

    task ack_prefetch;
        begin
            pf_ack = 1'b1;
            @(posedge clk); #1;
            pf_ack = 1'b0;
            @(posedge clk); #1;
        end
    endtask

    task drive_lru_update;
        input [7:0] page;
        begin
            lru_update_page = page;
            lru_update_en = 1'b1;
            @(posedge clk); #1;
            lru_update_en = 1'b0;
            @(posedge clk); #1;
        end
    endtask

    initial begin
        pass_a = 0;
        fail_a = 0;
        pass_b = 0;
        fail_b = 0;
        saw_pf = 1'b0;
        saw_pf_page = 5'd0;
        saw_pf_sess = 3'd0;
        saw_free = 1'b0;

        obs_session_id = 3'd0;
        obs_token_pos = 12'd0;
        obs_rd_req = 1'b0;
        pf_ack = 1'b0;
        almost_full = 1'b0;
        lru_update_en = 1'b0;
        lru_update_page = 8'd0;
        evict_ack = 1'b0;

        for (i = 0; i < 256; i = i + 1)
            page_session_map[i] = i[2:0];
        page_session_map[5] = 3'd6;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;

        $display("");
        $display("=== Section A: prefetch_ctrl tests ===");

        $display("");
        $display("A1: No prefetch on non-sequential same-page reads");
        obs_read(3'd0, 12'd3, saw_pf, saw_pf_sess, saw_pf_page);
        check_a(!saw_pf, "first random read no prefetch");
        obs_read(3'd0, 12'd9, saw_pf, saw_pf_sess, saw_pf_page);
        check_a(!saw_pf, "same page random read no prefetch");

        $display("");
        $display("A2: Sequential reads within one page");
        obs_read(3'd2, 12'd0, saw_pf, saw_pf_sess, saw_pf_page);
        check_a(!saw_pf, "page 0 token 0 no prefetch");
        obs_read(3'd2, 12'd1, saw_pf, saw_pf_sess, saw_pf_page);
        check_a(!saw_pf, "page 0 token 1 no prefetch");
        obs_read(3'd2, 12'd15, saw_pf, saw_pf_sess, saw_pf_page);
        check_a(!saw_pf, "page 0 token 15 no prefetch");

        $display("");
        $display("A3: Crossing tokens 15 to 16");
        obs_read(3'd0, 12'd15, saw_pf, saw_pf_sess, saw_pf_page);
        obs_read(3'd0, 12'd16, saw_pf, saw_pf_sess, saw_pf_page);
        check_a(saw_pf, "pf_req asserted on 15 to 16");
        check_a((saw_pf_sess == 3'd0) && (saw_pf_page == 5'd1),
                "prefetch targets session 0 page 1");

        $display("");
        $display("A4: Ack fills buffer entry 0");
        ack_prefetch();
        check_a(pf_buf_valid[0], "buffer entry 0 valid");
        check_a((pf_buf_sess[0] == 3'd0) && (pf_buf_page[0] == 5'd1),
                "buffer entry 0 holds session 0 page 1");

        $display("");
        $display("A5: Second crossing fills entry 1");
        obs_read(3'd0, 12'd31, saw_pf, saw_pf_sess, saw_pf_page);
        obs_read(3'd0, 12'd32, saw_pf, saw_pf_sess, saw_pf_page);
        check_a(saw_pf && (saw_pf_page == 5'd2), "prefetch page 2 requested");
        ack_prefetch();
        check_a(pf_buf_valid[1], "buffer entry 1 valid");
        check_a((pf_buf_sess[1] == 3'd0) && (pf_buf_page[1] == 5'd2),
                "buffer entry 1 holds session 0 page 2");

        $display("");
        $display("A6: Third crossing overwrites older entry");
        obs_read(3'd0, 12'd47, saw_pf, saw_pf_sess, saw_pf_page);
        obs_read(3'd0, 12'd48, saw_pf, saw_pf_sess, saw_pf_page);
        check_a(saw_pf && (saw_pf_page == 5'd3), "prefetch page 3 requested");
        ack_prefetch();
        check_a((pf_buf_valid[0] && pf_buf_sess[0] == 3'd0 &&
                 pf_buf_page[0] == 5'd3),
                "older entry overwritten by page 3");
        check_a((pf_buf_valid[1] && pf_buf_page[1] == 5'd2),
                "newer entry remains page 2");

        $display("");
        $display("A7: Multi-session pattern isolation");
        obs_read(3'd1, 12'd15, saw_pf, saw_pf_sess, saw_pf_page);
        check_a(!saw_pf, "session 1 first boundary token no prefetch");
        check_a((pf_buf_sess[0] == 3'd0) && (pf_buf_page[0] == 5'd3) &&
                (pf_buf_sess[1] == 3'd0) && (pf_buf_page[1] == 5'd2),
                "session 0 buffer state unchanged");
        obs_read(3'd1, 12'd16, saw_pf, saw_pf_sess, saw_pf_page);
        check_a(saw_pf && (saw_pf_sess == 3'd1) &&
                (saw_pf_page == 5'd1),
                "session 1 crossing detected independently");

        $display("");
        $display("=== Section B: eviction_engine tests ===");

        $display("");
        $display("B1: almost_full low");
        repeat (20) @(posedge clk);
        check_b(evict_valid == 1'b0, "no eviction when almost_full is 0");

        $display("");
        $display("B2: Populate LRU and trigger scan");
        for (i = 0; i < 256; i = i + 1) begin
            if (i != 5)
                drive_lru_update(i[7:0]);
        end
        almost_full = 1'b1;
        @(posedge clk); #1;
        for (i = 0; i < 270; i = i + 1) begin
            @(posedge clk); #1;
            if (evict_valid)
                i = 270;
        end
        check_b(evict_valid, "evict_valid asserts after scan");
        check_b(evict_page_id == 8'd5, "evict_page_id is page 5");

        $display("");
        $display("B3: Evict session id");
        check_b(evict_session_id == 3'd6,
                "evict_session_id matches reverse map");

        $display("");
        $display("B4: Host ack frees page");
        evict_ack = 1'b1;
        @(posedge clk); #1;
        evict_ack = 1'b0;
        saw_free = 1'b0;
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk); #1;
            if (free_req && free_page_id == 8'd5)
                saw_free = 1'b1;
        end
        check_b(saw_free, "free_req pulses for page 5");

        $display("");
        $display("B5: Return to idle after free");
        @(posedge clk); #1;
        check_b(evict_valid == 1'b0, "evict_valid deasserts after free");

        $display("");
        $display("B6: almost_full low prevents new scan");
        almost_full = 1'b0;
        repeat (40) @(posedge clk);
        check_b(evict_valid == 1'b0, "no new eviction after almost_full low");

        $display("");
        $display("============================================");
        $display("Section A passed : %0d", pass_a);
        $display("Section A failed : %0d", fail_a);
        $display("Section B passed : %0d", pass_b);
        $display("Section B failed : %0d", fail_b);
        $display("Total passed     : %0d", pass_a + pass_b);
        $display("Total failed     : %0d", fail_a + fail_b);
        if ((fail_a + fail_b) == 0)
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
