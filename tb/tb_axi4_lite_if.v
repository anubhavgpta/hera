`timescale 1ns/1ps
// Testbench -- axi4_lite_if
// AXI4-Lite BFM with self-checking register, status, and IRQ tests.

module tb_axi4_lite_if;

    localparam NUM_SESSIONS = 8;
    localparam TOTAL_PAGES  = 256;

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

    reg  [7:0] pages_free_i;
    reg  [7:0] pages_used_i;
    reg        almost_full_i;
    reg        evict_pending_i;
    reg  [7:0] evict_page_id_i;
    reg  [2:0] evict_session_id_i;
    reg        quota_exceeded_i;
    reg        sec_fault_i;

    wire       global_enable;
    wire       soft_reset;
    wire [2:0] active_session_id;
    wire [7:0] max_pages_per_session;
    wire       irq;

    axi4_lite_if #(
        .NUM_SESSIONS(NUM_SESSIONS),
        .TOTAL_PAGES(TOTAL_PAGES)
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
        .pages_free_i(pages_free_i),
        .pages_used_i(pages_used_i),
        .almost_full_i(almost_full_i),
        .evict_pending_i(evict_pending_i),
        .evict_page_id_i(evict_page_id_i),
        .evict_session_id_i(evict_session_id_i),
        .quota_exceeded_i(quota_exceeded_i),
        .sec_fault_i(sec_fault_i),
        .global_enable(global_enable),
        .soft_reset(soft_reset),
        .active_session_id(active_session_id),
        .max_pages_per_session(max_pages_per_session),
        .irq(irq)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    integer pass_cnt, fail_cnt;
    integer bresp_total, bresp_bad;
    integer rresp_total, rresp_bad;
    integer cyc;
    reg [31:0] rd_tmp;
    reg soft_seen;

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

    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk); #1;
            s_axi_awaddr  = addr;
            s_axi_wdata   = data;
            s_axi_wstrb   = 4'hF;
            s_axi_awvalid = 1'b1;
            s_axi_wvalid  = 1'b1;
            while (!(s_axi_awready && s_axi_wready)) begin
                @(posedge clk); #1;
            end
            @(posedge clk); #1;
            s_axi_awvalid = 1'b0;
            s_axi_wvalid  = 1'b0;
            s_axi_bready  = 1'b1;
            while (!s_axi_bvalid) begin
                @(posedge clk); #1;
            end
            bresp_total = bresp_total + 1;
            if (s_axi_bresp != 2'b00)
                bresp_bad = bresp_bad + 1;
            @(posedge clk); #1;
            s_axi_bready = 1'b0;
        end
    endtask

    task axi_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk); #1;
            s_axi_araddr  = addr;
            s_axi_arvalid = 1'b1;
            while (!s_axi_arready) begin
                @(posedge clk); #1;
            end
            @(posedge clk); #1;
            s_axi_arvalid = 1'b0;
            s_axi_rready  = 1'b1;
            while (!s_axi_rvalid) begin
                @(posedge clk); #1;
            end
            data = s_axi_rdata;
            rresp_total = rresp_total + 1;
            if (s_axi_rresp != 2'b00)
                rresp_bad = rresp_bad + 1;
            @(posedge clk); #1;
            s_axi_rready = 1'b0;
        end
    endtask

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        bresp_total = 0;
        bresp_bad = 0;
        rresp_total = 0;
        rresp_bad = 0;
        rd_tmp = 32'd0;
        soft_seen = 1'b0;

        s_axi_awvalid = 1'b0;
        s_axi_awaddr = 32'd0;
        s_axi_wvalid = 1'b0;
        s_axi_wdata = 32'd0;
        s_axi_wstrb = 4'd0;
        s_axi_bready = 1'b0;
        s_axi_arvalid = 1'b0;
        s_axi_araddr = 32'd0;
        s_axi_rready = 1'b0;

        pages_free_i = 8'd0;
        pages_used_i = 8'd0;
        almost_full_i = 1'b0;
        evict_pending_i = 1'b0;
        evict_page_id_i = 8'd0;
        evict_session_id_i = 3'd0;
        quota_exceeded_i = 1'b0;
        sec_fault_i = 1'b0;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;

        $display("");
        $display("=== Test 1: CTRL global_enable ===");
        axi_write(32'h00000000, 32'h00000001);
        axi_read(32'h00000000, rd_tmp);
        check_it(rd_tmp[0] == 1'b1, "CTRL[0] readback is 1");
        check_it(global_enable == 1'b1, "global_enable output is 1");

        $display("");
        $display("=== Test 2: SESSION_CFG ===");
        axi_write(32'h00000004, 32'h00000003);
        axi_read(32'h00000004, rd_tmp);
        check_it(rd_tmp[2:0] == 3'd3, "SESSION_CFG readback is 3");
        check_it(active_session_id == 3'd3, "active_session_id output is 3");

        $display("");
        $display("=== Test 3: PAGE_CFG ===");
        axi_write(32'h00000008, 32'h00000020);
        axi_read(32'h00000008, rd_tmp);
        check_it(rd_tmp[7:0] == 8'h20, "PAGE_CFG readback is 0x20");
        check_it(max_pages_per_session == 8'h20,
                 "max_pages_per_session output is 0x20");

        $display("");
        $display("=== Test 4: STATUS fields ===");
        pages_free_i = 8'hF0;
        pages_used_i = 8'h10;
        almost_full_i = 1'b0;
        evict_pending_i = 1'b0;
        axi_read(32'h00000010, rd_tmp);
        check_it(rd_tmp[7:0] == 8'hF0, "STATUS pages_free matches");
        check_it(rd_tmp[15:8] == 8'h10, "STATUS pages_used matches");
        check_it(rd_tmp[16] == 1'b0, "STATUS almost_full is 0");
        check_it(rd_tmp[17] == 1'b0, "STATUS evict_pending is 0");

        $display("");
        $display("=== Test 5: IRQ almost_full unmasked ===");
        almost_full_i = 1'b1;
        axi_write(32'h00000018, 32'h00000000);
        @(posedge clk); #1;
        check_it(irq == 1'b1, "irq asserts for unmasked almost_full");

        $display("");
        $display("=== Test 6: IRQ almost_full masked ===");
        axi_write(32'h00000018, 32'h00000001);
        @(posedge clk); #1;
        check_it(irq == 1'b0, "irq deasserts when almost_full masked");

        $display("");
        $display("=== Test 7: EVICT_ADDR fields ===");
        evict_page_id_i = 8'hAB;
        evict_session_id_i = 3'd3;
        evict_pending_i = 1'b1;
        axi_read(32'h00000014, rd_tmp);
        check_it(rd_tmp[7:0] == 8'hAB, "EVICT_ADDR page id matches");
        check_it(rd_tmp[10:8] == 3'd3, "EVICT_ADDR session id matches");

        $display("");
        $display("=== Test 8: CTRL soft_reset pulse ===");
        soft_seen = 1'b0;
        fork
            begin : soft_watch
                for (cyc = 0; cyc < 8; cyc = cyc + 1) begin
                    @(posedge clk); #1;
                    if (soft_reset)
                        soft_seen = 1'b1;
                end
            end
            begin : soft_write
                axi_write(32'h00000000, 32'h00000002);
            end
        join
        check_it(soft_seen, "soft_reset output pulses");
        axi_read(32'h00000000, rd_tmp);
        check_it(rd_tmp[1] == 1'b0, "CTRL[1] readback is not sticky");

        $display("");
        $display("=== Test 9: STATUS live almost_full ===");
        evict_pending_i = 1'b0;
        almost_full_i = 1'b0;
        axi_read(32'h00000010, rd_tmp);
        check_it(rd_tmp[16] == 1'b0, "STATUS live almost_full low");
        almost_full_i = 1'b1;
        axi_read(32'h00000010, rd_tmp);
        check_it(rd_tmp[16] == 1'b1, "STATUS live almost_full high");

        $display("");
        $display("=== Test 10: AXI response codes ===");
        check_it((bresp_total == 6) && (bresp_bad == 0),
                 "all write responses OKAY");
        check_it((rresp_total == 8) && (rresp_bad == 0),
                 "all read responses OKAY");

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
