`timescale 1ns/1ps
// Testbench -- block_table
// 8-step exhaustive sequence; PASS/FAIL per check.
//
// Address convention: {session_id[2:0], logical_page[4:0]} ??' 8-bit flat index.
// Deterministic physical IDs: physical = session * 32 + logical_page.
// rd outputs have 1-cycle latency -- address is presented one cycle before sampling.

module tb_block_table;

    // ----------------------------------------------------------------
    // DUT wiring
    // ----------------------------------------------------------------
    reg        clk, rst_n;
    reg        wr_en;
    reg  [2:0] wr_session_id;
    reg  [4:0] wr_logical_page;
    reg  [7:0] wr_physical_page;
    reg  [2:0] rd_session_id;
    reg  [4:0] rd_logical_page;
    wire [7:0] rd_physical_page;
    wire       rd_valid;
    reg        inv_en;
    reg  [2:0] inv_session_id;
    reg  [4:0] inv_logical_page;

    block_table #(
        .NUM_SESSIONS  (8),
        .LOGICAL_PAGES (32),
        .TOTAL_PAGES   (256)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .wr_en            (wr_en),
        .wr_session_id    (wr_session_id),
        .wr_logical_page  (wr_logical_page),
        .wr_physical_page (wr_physical_page),
        .rd_session_id    (rd_session_id),
        .rd_logical_page  (rd_logical_page),
        .rd_physical_page (rd_physical_page),
        .rd_valid         (rd_valid),
        .inv_en           (inv_en),
        .inv_session_id   (inv_session_id),
        .inv_logical_page (inv_logical_page)
    );

    // 100 MHz clock
    initial clk = 1'b0;
    always  #5 clk = ~clk;

    // ----------------------------------------------------------------
    // Bookkeeping
    // ----------------------------------------------------------------
    integer pass_cnt, fail_cnt;
    integer s, p;
    reg [7:0] expected_phys;

    // ----------------------------------------------------------------
    // Check helper (message fits in 32 ASCII chars = 256 bits)
    // ----------------------------------------------------------------
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
    // Helper -- blocking single-cycle write
    // ----------------------------------------------------------------
    task do_write;
        input [2:0] sid;
        input [4:0] lp;
        input [7:0] phys;
        begin
            wr_en = 1'b1;
            wr_session_id    = sid;
            wr_logical_page  = lp;
            wr_physical_page = phys;
            @(posedge clk); #1;
            wr_en = 1'b0;
        end
    endtask

    // Helper -- blocking single-cycle invalidate
    task do_inv;
        input [2:0] sid;
        input [4:0] lp;
        begin
            inv_en = 1'b1;
            inv_session_id   = sid;
            inv_logical_page = lp;
            @(posedge clk); #1;
            inv_en = 1'b0;
        end
    endtask

    // Helper -- present rd address and capture outputs after 1 clock
    task do_read;
        input  [2:0] sid;
        input  [4:0] lp;
        output [7:0] phys_out;
        output       valid_out;
        begin
            rd_session_id   = sid;
            rd_logical_page = lp;
            @(posedge clk); #1;
            phys_out  = rd_physical_page;
            valid_out = rd_valid;
        end
    endtask

    // ----------------------------------------------------------------
    // Main stimulus
    // ----------------------------------------------------------------
    reg [7:0] rd_phys_tmp;
    reg       rd_valid_tmp;
    integer   t3_fails, t8_fails;

    initial begin
        pass_cnt = 0; fail_cnt = 0;
        wr_en  = 1'b0;  inv_en = 1'b0;
        wr_session_id  = 3'd0;  wr_logical_page  = 5'd0;  wr_physical_page = 8'd0;
        rd_session_id  = 3'd0;  rd_logical_page  = 5'd0;
        inv_session_id = 3'd0;  inv_logical_page = 5'd0;
        rd_phys_tmp    = 8'd0;  rd_valid_tmp     = 1'b0;
        t3_fails       = 0;     t8_fails         = 0;

        // ============================================================
        // RESET
        // ============================================================
        rst_n = 1'b0;
        repeat(4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;   // one cycle for reset path to settle rd_valid

        // ============================================================
        // Test 1 -- After reset, rd_valid == 0 for sampled addresses
        // ============================================================
        $display("");
        $display("=== Test 1: rd_valid==0 after reset (sampled) ===");
        begin : t1_block
            integer t1_fails;
            t1_fails = 0;
            for (s = 0; s < 8; s = s + 2) begin
                for (p = 0; p < 32; p = p + 8) begin
                    do_read(s[2:0], p[4:0], rd_phys_tmp, rd_valid_tmp);
                    if (rd_valid_tmp !== 1'b0) begin
                        $display("  FAIL: s=%0d p=%0d rd_valid=%b after reset",
                                 s, p, rd_valid_tmp);
                        t1_fails = t1_fails + 1;
                        fail_cnt = fail_cnt + 1;
                    end
                end
            end
            if (t1_fails == 0) begin
                $display("  PASS: rd_valid==0 for all 16 sampled addresses");
                pass_cnt = pass_cnt + 1;
            end
        end

        // ============================================================
        // Test 2 -- Write all 256 entries with deterministic physical IDs
        //          physical_page = session_id * 32 + logical_page
        // ============================================================
        $display("");
        $display("=== Test 2: Write all 256 entries ===");
        for (s = 0; s < 8; s = s + 1) begin
            for (p = 0; p < 32; p = p + 1) begin
                wr_en            = 1'b1;
                wr_session_id    = s[2:0];
                wr_logical_page  = p[4:0];
                wr_physical_page = s * 32 + p;
                @(posedge clk); #1;
            end
        end
        wr_en = 1'b0;
        $display("  INFO: All 256 entries written");

        // ============================================================
        // Test 3 -- Read back all 256 entries; verify data and rd_valid
        // ============================================================
        $display("");
        $display("=== Test 3: Read-back all 256 entries ===");
        t3_fails = 0;
        for (s = 0; s < 8; s = s + 1) begin
            for (p = 0; p < 32; p = p + 1) begin
                do_read(s[2:0], p[4:0], rd_phys_tmp, rd_valid_tmp);
                expected_phys = s * 32 + p;
                if (rd_valid_tmp !== 1'b1 || rd_phys_tmp !== expected_phys) begin
                    $display("  FAIL: s=%0d p=%0d exp=%0d got=%0d valid=%b",
                             s, p, expected_phys, rd_phys_tmp, rd_valid_tmp);
                    t3_fails = t3_fails + 1;
                    fail_cnt = fail_cnt + 1;
                end
            end
        end
        if (t3_fails == 0) begin
            $display("  PASS: All 256 entries match expected data, rd_valid==1");
            pass_cnt = pass_cnt + 1;
        end

        // ============================================================
        // Test 4 -- Write-first: simultaneous wr and rd to same address
        //          Overwrite (s=3, p=7) with 0xAB while reading it;
        //          registered output must capture the written value.
        // ============================================================
        $display("");
        $display("=== Test 4: Write-first semantics ===");
        begin : t4_block
            wr_en            = 1'b1;
            wr_session_id    = 3'd3;
            wr_logical_page  = 5'd7;
            wr_physical_page = 8'hAB;
            rd_session_id    = 3'd3;   // same address as write
            rd_logical_page  = 5'd7;
            @(posedge clk); #1;
            wr_en = 1'b0;
            // rd outputs must reflect the forwarded write value
            check_it(rd_physical_page == 8'hAB, "Write-first: data==0xAB");
            check_it(rd_valid == 1'b1,           "Write-first: rd_valid==1");
        end

        // ============================================================
        // Tests 5/6 -- Invalidate 4 entries, then verify rd_valid==0
        // ============================================================
        $display("");
        $display("=== Tests 5/6: Invalidate 4 entries, verify rd_valid==0 ===");

        // Apply 4 invalidations (each 1 cycle)
        do_inv(3'd1, 5'd5);
        do_inv(3'd2, 5'd10);
        do_inv(3'd5, 5'd20);
        do_inv(3'd7, 5'd31);

        // Read each invalidated slot; rd_valid must be 0
        do_read(3'd1, 5'd5,  rd_phys_tmp, rd_valid_tmp);
        check_it(!rd_valid_tmp, "Inv (s=1,p=5) : rd_valid==0");

        do_read(3'd2, 5'd10, rd_phys_tmp, rd_valid_tmp);
        check_it(!rd_valid_tmp, "Inv (s=2,p=10): rd_valid==0");

        do_read(3'd5, 5'd20, rd_phys_tmp, rd_valid_tmp);
        check_it(!rd_valid_tmp, "Inv (s=5,p=20): rd_valid==0");

        do_read(3'd7, 5'd31, rd_phys_tmp, rd_valid_tmp);
        check_it(!rd_valid_tmp, "Inv (s=7,p=31): rd_valid==0");

        // ============================================================
        // Test 7 -- Overwrite one invalidated entry; rd_valid must return to 1
        // ============================================================
        $display("");
        $display("=== Test 7: Re-write invalidated entry (s=1, p=5) ===");
        do_write(3'd1, 5'd5, 8'hCD);
        do_read (3'd1, 5'd5, rd_phys_tmp, rd_valid_tmp);
        check_it(rd_valid_tmp == 1'b1,        "Re-write: rd_valid==1");
        check_it(rd_phys_tmp  == 8'hCD,       "Re-write: data==0xCD");

        // ============================================================
        // Test 8 -- Verify untouched sessions are unaffected
        //   Session 0: fully intact (no inv or overwrite ever)
        //   Session 4: fully intact
        //   Spot-check session 6: also untouched
        // ============================================================
        $display("");
        $display("=== Test 8: Unaffected sessions intact ===");
        t8_fails = 0;

        // Session 0 -- physical = 0*32+p = p
        for (p = 0; p < 32; p = p + 1) begin
            do_read(3'd0, p[4:0], rd_phys_tmp, rd_valid_tmp);
            expected_phys = p[7:0];
            if (rd_valid_tmp !== 1'b1 || rd_phys_tmp !== expected_phys) begin
                $display("  FAIL: s=0 p=%0d exp=%0d got=%0d valid=%b",
                         p, expected_phys, rd_phys_tmp, rd_valid_tmp);
                t8_fails = t8_fails + 1;
                fail_cnt = fail_cnt + 1;
            end
        end

        // Session 4 -- physical = 4*32+p = 128+p
        for (p = 0; p < 32; p = p + 1) begin
            do_read(3'd4, p[4:0], rd_phys_tmp, rd_valid_tmp);
            expected_phys = 4 * 32 + p;
            if (rd_valid_tmp !== 1'b1 || rd_phys_tmp !== expected_phys) begin
                $display("  FAIL: s=4 p=%0d exp=%0d got=%0d valid=%b",
                         p, expected_phys, rd_phys_tmp, rd_valid_tmp);
                t8_fails = t8_fails + 1;
                fail_cnt = fail_cnt + 1;
            end
        end

        // Session 6 -- physical = 6*32+p = 192+p
        for (p = 0; p < 32; p = p + 1) begin
            do_read(3'd6, p[4:0], rd_phys_tmp, rd_valid_tmp);
            expected_phys = 6 * 32 + p;
            if (rd_valid_tmp !== 1'b1 || rd_phys_tmp !== expected_phys) begin
                $display("  FAIL: s=6 p=%0d exp=%0d got=%0d valid=%b",
                         p, expected_phys, rd_phys_tmp, rd_valid_tmp);
                t8_fails = t8_fails + 1;
                fail_cnt = fail_cnt + 1;
            end
        end

        if (t8_fails == 0) begin
            $display("  PASS: Sessions 0, 4, 6 fully intact (96 entries)");
            pass_cnt = pass_cnt + 1;
        end

        // ============================================================
        // Summary
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

    // Watchdog
    initial begin
        #5_000_000;
        $display("TIMEOUT -- simulation did not complete");
        $finish;
    end

endmodule

