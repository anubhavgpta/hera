`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import hera_uvm_pkg::*;

module tb_top;

    localparam TOTAL_PAGES      = 256;
    localparam PAGE_SIZE_TOKENS = 16;
    localparam HEAD_DIM         = 64;
    localparam NUM_SESSIONS     = 8;
    localparam DATA_WIDTH       = 16;
    localparam SRAM_BANKS       = 4;
    localparam KV_W             = DATA_WIDTH * HEAD_DIM; // 1024

    // ----------------------------------------------------------------
    // Clock and reset
    // ----------------------------------------------------------------
    logic clk, rst_n;

    initial clk = 0;
    always #5 clk = ~clk; // 100 MHz

    initial begin
        rst_n = 0;
        repeat(10) @(posedge clk);
        @(negedge clk);
        rst_n = 1;
    end

    // ----------------------------------------------------------------
    // Interfaces
    // ----------------------------------------------------------------
    hera_axi4_lite_if           axi_if   (.clk(clk), .rst_n(rst_n));
    hera_kv_wr_if #(.KV_W(KV_W)) kv_wr_if (.clk(clk));
    hera_kv_rd_if #(.KV_W(KV_W)) kv_rd_if (.clk(clk));
    hera_evict_if               evict_if (.clk(clk));

    // ----------------------------------------------------------------
    // DUT
    // ----------------------------------------------------------------
    kv_cache_ctrl #(
        .TOTAL_PAGES     (TOTAL_PAGES),
        .PAGE_SIZE_TOKENS(PAGE_SIZE_TOKENS),
        .HEAD_DIM        (HEAD_DIM),
        .NUM_SESSIONS    (NUM_SESSIONS),
        .DATA_WIDTH      (DATA_WIDTH),
        .SRAM_BANKS      (SRAM_BANKS)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),

        // AXI4-Lite
        .s_axi_awvalid    (axi_if.awvalid),
        .s_axi_awready    (axi_if.awready),
        .s_axi_awaddr     (axi_if.awaddr),
        .s_axi_wvalid     (axi_if.wvalid),
        .s_axi_wready     (axi_if.wready),
        .s_axi_wdata      (axi_if.wdata),
        .s_axi_wstrb      (axi_if.wstrb),
        .s_axi_bvalid     (axi_if.bvalid),
        .s_axi_bready     (axi_if.bready),
        .s_axi_bresp      (axi_if.bresp),
        .s_axi_arvalid    (axi_if.arvalid),
        .s_axi_arready    (axi_if.arready),
        .s_axi_araddr     (axi_if.araddr),
        .s_axi_rvalid     (axi_if.rvalid),
        .s_axi_rready     (axi_if.rready),
        .s_axi_rdata      (axi_if.rdata),
        .s_axi_rresp      (axi_if.rresp),
        .irq              (axi_if.irq),

        // KV write
        .wr_req           (kv_wr_if.wr_req),
        .wr_session_id    (kv_wr_if.wr_session_id),
        .wr_token_pos     (kv_wr_if.wr_token_pos),
        .wr_k_data        (kv_wr_if.wr_k_data),
        .wr_v_data        (kv_wr_if.wr_v_data),
        .wr_ack           (kv_wr_if.wr_ack),

        // KV read
        .rd_req           (kv_rd_if.rd_req),
        .rd_session_id    (kv_rd_if.rd_session_id),
        .rd_token_start   (kv_rd_if.rd_token_start),
        .rd_token_end     (kv_rd_if.rd_token_end),
        .rd_k_data        (kv_rd_if.rd_k_data),
        .rd_v_data        (kv_rd_if.rd_v_data),
        .rd_valid         (kv_rd_if.rd_valid),
        .rd_last          (kv_rd_if.rd_last),
        .rd_busy          (kv_rd_if.rd_busy),

        // Eviction
        .evict_valid      (evict_if.evict_valid),
        .evict_page_id    (evict_if.evict_page_id),
        .evict_session_id (evict_if.evict_session_id),
        .evict_ack        (evict_if.evict_ack)
    );

    // ----------------------------------------------------------------
    // UVM startup — register virtual interfaces then run test
    // ----------------------------------------------------------------
    initial begin
        uvm_config_db #(virtual hera_axi4_lite_if)::set(
            null, "uvm_test_top.*", "axi_vif",    axi_if);
        uvm_config_db #(virtual hera_kv_wr_if)::set(
            null, "uvm_test_top.*", "kv_wr_vif",  kv_wr_if);
        uvm_config_db #(virtual hera_kv_rd_if)::set(
            null, "uvm_test_top.*", "kv_rd_vif",  kv_rd_if);
        uvm_config_db #(virtual hera_evict_if)::set(
            null, "uvm_test_top.*", "evict_vif",  evict_if);
        run_test();
    end

    // ----------------------------------------------------------------
    // Global simulation timeout
    // ----------------------------------------------------------------
    initial begin
        #50_000_000;
        `uvm_fatal("TIMEOUT", "Simulation exceeded 50 ms — check for hung driver")
    end

endmodule
