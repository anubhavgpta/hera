`timescale 1ns/1ps
// Testbench -- block_allocator
// Exhaustive 9-step sequence; prints PASS/FAIL per check.
//
// NOTE on 8-bit page counts
//   pages_free and pages_used are [7:0].  256 free pages maps to 8'h00
//   because 256 truncates to 0 mod 256.  Comparisons against 8'd0 are
//   therefore used where the spec says "== 256".

module tb_block_allocator;

    // ----------------------------------------------------------------
    // DUT wiring
    // ----------------------------------------------------------------
    reg        clk, rst_n;
    reg        alloc_req;
    reg  [2:0] alloc_session_id;
    wire       alloc_ack;
    wire [7:0] alloc_page_id;
    reg        free_req;
    reg  [7:0] free_page_id;
    wire [7:0] pages_free;
    wire [7:0] pages_used;
    wire       almost_full;

    block_allocator #(.TOTAL_PAGES(256)) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .alloc_req        (alloc_req),
        .alloc_session_id (alloc_session_id),
        .alloc_ack        (alloc_ack),
        .alloc_page_id    (alloc_page_id),
        .free_req         (free_req),
        .free_page_id     (free_page_id),
        .pages_free       (pages_free),
        .pages_used       (pages_used),
        .almost_full      (almost_full)
    );

    // 100 MHz clock (10 ns period)
    initial clk = 1'b0;
    always  #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Bookkeeping
    // ----------------------------------------------------------------
    integer pass_cnt, fail_cnt;
    integer i;
    reg [7:0] collected [0:255];   // page IDs received during mass alloc
    reg       seen      [0:255];   // uniqueness bitmap
    integer   alloc_cnt;
    reg       almost_full_seen;
    reg       dup_found;

    // ----------------------------------------------------------------
    // Check helper -- inline macro-style
    // ----------------------------------------------------------------
    // Usage: call check_it(condition, "description")
    // Verilog-2001: pass message as a 256-bit reg holding ASCII bytes
    task check_it;
        input        cond;
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

    // ----------------------------------------------------------------
    // Main sequence
    // ----------------------------------------------------------------
    initial begin
        // -- Init signals
        pass_cnt         = 0;
        fail_cnt         = 0;
        alloc_req        = 1'b0;
        free_req         = 1'b0;
        free_page_id     = 8'd0;
        alloc_session_id = 3'd0;
        almost_full_seen = 1'b0;
        alloc_cnt        = 0;

        // ============================================================
        // RESET
        // ============================================================
        rst_n = 1'b0;
        repeat(5) @(posedge clk);
        rst_n = 1'b1;

        // Wait for init FSM to fill all 256 LUTRAM slots (256 cycles)
        // plus a few cycles of margin
        repeat(262) @(posedge clk);
        #1; // settle after last NBA phase

        $display("");
        $display("=== Test 1: Post-reset counts ===");
        // 256 free pages ??' pages_free wraps to 8'h00 (256 mod 256)
        check_it(pages_free == 8'd0,   "pages_free==0x00 (represents 256)");
        check_it(pages_used == 8'd0,   "pages_used==0");
        check_it(!almost_full,          "almost_full deasserted");

        // ============================================================
        // TESTS 2, 3, 4 -- Allocate all 256 pages back-to-back
        // ============================================================
        $display("");
        $display("=== Tests 2/3/4: Allocate all 256 pages ===");
        alloc_cnt        = 0;
        almost_full_seen = 1'b0;

        alloc_req = 1'b1;
        repeat(256) begin
            @(posedge clk); #1;
            // Sample after NBA phase: outputs reflect THIS posedge's alloc
            if (almost_full)
                almost_full_seen = 1'b1;
            if (alloc_ack) begin
                collected[alloc_cnt] = alloc_page_id;
                alloc_cnt = alloc_cnt + 1;
            end else begin
                $display("  FAIL: alloc_ack missing at iteration %0d (count=%0d)",
                         alloc_cnt, alloc_cnt);
                fail_cnt = fail_cnt + 1;
            end
        end
        alloc_req = 1'b0;
        @(posedge clk); #1;   // flush: alloc_ack ??' 0

        // Test 2: received exactly 256 acks
        check_it(alloc_cnt == 256, "Received alloc_ack for all 256 pages");

        // Test 3: uniqueness -- every page ID must appear exactly once
        for (i = 0; i < 256; i = i + 1) seen[i] = 1'b0;
        dup_found = 1'b0;
        for (i = 0; i < 256; i = i + 1) begin
            if (seen[collected[i]]) begin
                $display("  FAIL: Duplicate page_id %0d (alloc index %0d)",
                         collected[i], i);
                dup_found = 1'b1;
                fail_cnt  = fail_cnt + 1;
            end
            seen[collected[i]] = 1'b1;
        end
        if (!dup_found) begin
            $display("  PASS: No duplicate page IDs");
            pass_cnt = pass_cnt + 1;
        end

        // Test 4: almost_full must have fired before the list emptied
        check_it(almost_full_seen, "almost_full asserted before final pages allocated");

        // ============================================================
        // TEST 5 -- alloc_req on empty list must NOT assert alloc_ack
        // ============================================================
        $display("");
        $display("=== Test 5: Alloc on empty list ===");
        alloc_req = 1'b1;
        @(posedge clk); #1;
        check_it(!alloc_ack,          "alloc_ack suppressed when list empty");
        alloc_req = 1'b0;
        @(posedge clk); #1;

        check_it(pages_free == 8'd0,  "pages_free==0 (list empty after all allocs)");

        // ============================================================
        // TESTS 6, 7 -- Free all 256 pages in reversed order
        // ============================================================
        $display("");
        $display("=== Tests 6/7: Free all 256 pages (reversed order) ===");
        for (i = 255; i >= 0; i = i - 1) begin
            free_req     = 1'b1;
            free_page_id = collected[i];
            @(posedge clk); #1;
            free_req = 1'b0;
        end
        @(posedge clk); #1;

        // 256 pages free ??' pages_free wraps to 8'h00
        check_it(pages_free == 8'd0,  "pages_free==0x00 (represents 256) after full free");
        check_it(pages_used == 8'd0,  "pages_used==0 after full free");

        // ============================================================
        // TEST 8 -- Allocate 10 pages to confirm recovery
        // ============================================================
        $display("");
        $display("=== Test 8: Recovery -- allocate 10 pages ===");
        alloc_cnt = 0;
        alloc_req = 1'b1;
        repeat(10) begin
            @(posedge clk); #1;
            if (alloc_ack) alloc_cnt = alloc_cnt + 1;
        end
        alloc_req = 1'b0;
        @(posedge clk); #1;

        check_it(alloc_cnt    == 10,    "Received 10 alloc_acks after recovery");
        check_it(pages_free   == 8'd246,"pages_free==246 after 10 allocs");
        check_it(pages_used   == 8'd10, "pages_used==10 after 10 allocs");
        check_it(!almost_full,          "almost_full deasserted (246 free)");

        // ============================================================
        // TEST 9 -- Summary
        // ============================================================
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

    // Simulation watchdog -- catch hangs
    initial begin
        #2_000_000;
        $display("TIMEOUT -- simulation did not finish in 2 ms");
        $finish;
    end

endmodule

