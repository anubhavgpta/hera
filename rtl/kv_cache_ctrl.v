`timescale 1ns/1ps
// Hera -- Top-Level Paged KV Cache Controller
//
// Integrates allocator, block table, read/write engine, AXI4-Lite control,
// prefetch controller, eviction engine, and four internal SRAM banks.
//
// Security hardening:
//   Quota enforcement: alloc is denied when a session exceeds
//   max_pages_per_session (0 = unlimited).  Denial sets quota_exceeded.
//   Zero-on-free: evicted pages are scrubbed to zero by rw_engine before
//   being returned to the free list, preventing cross-session data leakage.
//   Session isolation and AXI access control are enforced in rw_engine and
//   axi4_lite_if respectively.

module kv_cache_ctrl #(
    parameter TOTAL_PAGES      = 256,
    parameter PAGE_SIZE_TOKENS = 16,
    parameter HEAD_DIM         = 64,
    parameter NUM_SESSIONS     = 8,
    parameter DATA_WIDTH       = 16,
    parameter SRAM_BANKS       = 4
) (
    input clk,
    input rst_n,

    // AXI4-Lite host interface
    input         s_axi_awvalid,
    output        s_axi_awready,
    input  [31:0] s_axi_awaddr,
    input         s_axi_wvalid,
    output        s_axi_wready,
    input  [31:0] s_axi_wdata,
    input  [3:0]  s_axi_wstrb,
    output        s_axi_bvalid,
    input         s_axi_bready,
    output [1:0]  s_axi_bresp,
    input         s_axi_arvalid,
    output        s_axi_arready,
    input  [31:0] s_axi_araddr,
    output        s_axi_rvalid,
    input         s_axi_rready,
    output [31:0] s_axi_rdata,
    output [1:0]  s_axi_rresp,
    output        irq,

    // KV write interface
    input  wr_req,
    input  [2:0]  wr_session_id,
    input  [11:0] wr_token_pos,
    input  [DATA_WIDTH*HEAD_DIM-1:0] wr_k_data,
    input  [DATA_WIDTH*HEAD_DIM-1:0] wr_v_data,
    output reg wr_ack,

    // KV read interface
    input  rd_req,
    input  [2:0]  rd_session_id,
    input  [11:0] rd_token_start,
    input  [11:0] rd_token_end,
    output [DATA_WIDTH*HEAD_DIM-1:0] rd_k_data,
    output [DATA_WIDTH*HEAD_DIM-1:0] rd_v_data,
    output rd_valid,
    output rd_last,
    output rd_busy,

    // Eviction offload interface
    output       evict_valid,
    output [7:0] evict_page_id,
    output [2:0] evict_session_id,
    input        evict_ack
);

    // ------------------------------------------------------------------
    // Parameter guards -- simulation will abort on violation
    // ------------------------------------------------------------------
    initial begin
        if (TOTAL_PAGES > 256)
            $error("kv_cache_ctrl: TOTAL_PAGES > 256 exceeds allocator address width");
        if (NUM_SESSIONS > 8)
            $error("kv_cache_ctrl: NUM_SESSIONS > 8 exceeds 3-bit session_id encoding");
        if (SRAM_BANKS != 4)
            $error("kv_cache_ctrl: SRAM_BANKS must be 4 for this implementation");
    end

    // Silicon watermark -- same constant as axi4_lite_if for cross-check
    localparam [31:0] HERA_IP_ID = 32'h48455241; // ASCII "HERA"

    localparam KV_WIDTH   = DATA_WIDTH * HEAD_DIM;
    localparam SRAM_WIDTH = KV_WIDTH * 2;

    localparam WR_IDLE       = 3'd0;
    localparam WR_ALLOC_WAIT = 3'd2;
    localparam WR_TABLE_WAIT = 3'd3;
    localparam WR_START_RW   = 3'd4;
    localparam WR_WAIT_RW    = 3'd5;

    wire global_enable;
    wire soft_reset;
    wire [2:0] active_session_id;
    wire [7:0] max_pages_per_session;
    wire internal_rst_n = rst_n & ~soft_reset;

    wire [7:0] pages_free;
    wire [7:0] pages_used;
    wire almost_full;

    reg alloc_req;
    wire alloc_ack;
    wire [7:0] alloc_page_id;
    reg [2:0] alloc_session_id;

    reg bt_wr_en;
    reg [2:0] bt_wr_session;
    reg [4:0] bt_wr_logical;
    reg [7:0] bt_wr_physical;
    wire [2:0] bt_rd_session;
    wire [4:0] bt_rd_logical;
    wire [7:0] bt_rd_physical;
    wire bt_rd_valid;

    reg rw_wr_req;
    wire rw_wr_ack;
    wire rw_rd_req = global_enable & rd_req;

    wire [SRAM_BANKS-1:0] sram_ce;
    wire [SRAM_BANKS-1:0] sram_we;
    wire [7:0] sram_addr [SRAM_BANKS-1:0];
    wire [SRAM_WIDTH-1:0] sram_wdata;
    reg  [SRAM_WIDTH-1:0] sram_rdata [SRAM_BANKS-1:0];

    (* ram_style = "block" *) reg [KV_WIDTH-1:0] sram_k_mem0 [0:511];
    (* ram_style = "block" *) reg [KV_WIDTH-1:0] sram_v_mem0 [0:511];
    (* ram_style = "block" *) reg [KV_WIDTH-1:0] sram_k_mem1 [0:511];
    (* ram_style = "block" *) reg [KV_WIDTH-1:0] sram_v_mem1 [0:511];
    (* ram_style = "block" *) reg [KV_WIDTH-1:0] sram_k_mem2 [0:511];
    (* ram_style = "block" *) reg [KV_WIDTH-1:0] sram_v_mem2 [0:511];
    (* ram_style = "block" *) reg [KV_WIDTH-1:0] sram_k_mem3 [0:511];
    (* ram_style = "block" *) reg [KV_WIDTH-1:0] sram_v_mem3 [0:511];

    // Eviction engine free outputs -- intercepted by scrub FSM
    wire evict_free_req;
    wire [7:0] evict_free_page_id;

    reg [2:0] page_session_map [255:0];

    wire pf_req;
    reg pf_ack;
    wire [2:0] pf_session_id;
    wire [4:0] pf_logical_page;
    wire pf_buf_valid [1:0];
    wire [4:0] pf_buf_page [1:0];
    wire [2:0] pf_buf_sess [1:0];

    // ------------------------------------------------------------------
    // Write FSM state
    // ------------------------------------------------------------------
    reg [2:0] wr_state;
    reg [2:0] wr_sess_hold;
    reg [11:0] wr_token_hold;
    reg [KV_WIDTH-1:0] wr_k_hold;
    reg [KV_WIDTH-1:0] wr_v_hold;
    reg [4:0] wr_logical_hold;
    reg page_valid [0:NUM_SESSIONS-1][0:31];

    wire [4:0] wr_logical_page = wr_token_pos / PAGE_SIZE_TOKENS;

    // ------------------------------------------------------------------
    // Session quota tracking
    // ------------------------------------------------------------------
    reg [7:0] pages_per_session [0:NUM_SESSIONS-1];
    reg quota_exceeded_latch;

    // ------------------------------------------------------------------
    // Security fault latch (from rw_engine isolation check)
    // ------------------------------------------------------------------
    wire rw_sec_fault;
    reg sec_fault_latch;

    // ------------------------------------------------------------------
    // Zero-on-free scrub FSM
    // evict_free_req is intercepted here; block_allocator.free_req is
    // only pulsed after rw_engine confirms the page is zeroed.
    // ------------------------------------------------------------------
    localparam SCRUB_IDLE = 2'd0;
    localparam SCRUB_BUSY = 2'd1;

    reg [1:0] scrub_state;
    reg [7:0] scrub_page_hold;
    reg scrub_req_r;
    wire scrub_done;

    // Delayed free signals to block_allocator
    reg alloc_free_req_r;
    reg [7:0] alloc_free_page_r;

    // rw_engine scrub connections
    wire scrub_req_w  = scrub_req_r;
    wire [7:0] scrub_page_w = scrub_page_hold;

    integer i;
    integer j;

    // ------------------------------------------------------------------
    // Sub-module instances
    // ------------------------------------------------------------------

    axi4_lite_if #(
        .NUM_SESSIONS(NUM_SESSIONS),
        .TOTAL_PAGES(TOTAL_PAGES)
    ) u_axi (
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
        .pages_free_i(pages_free),
        .pages_used_i(pages_used),
        .almost_full_i(almost_full),
        .evict_pending_i(evict_valid),
        .evict_page_id_i(evict_page_id),
        .evict_session_id_i(evict_session_id),
        .quota_exceeded_i(quota_exceeded_latch),
        .sec_fault_i(sec_fault_latch),
        .global_enable(global_enable),
        .soft_reset(soft_reset),
        .active_session_id(active_session_id),
        .max_pages_per_session(max_pages_per_session),
        .irq(irq)
    );

    block_allocator #(
        .TOTAL_PAGES(TOTAL_PAGES)
    ) u_alloc (
        .clk(clk),
        .rst_n(internal_rst_n),
        .alloc_req(alloc_req),
        .alloc_session_id(alloc_session_id),
        .alloc_ack(alloc_ack),
        .alloc_page_id(alloc_page_id),
        .free_req(alloc_free_req_r),
        .free_page_id(alloc_free_page_r),
        .pages_free(pages_free),
        .pages_used(pages_used),
        .almost_full(almost_full)
    );

    block_table #(
        .NUM_SESSIONS(NUM_SESSIONS),
        .LOGICAL_PAGES(32),
        .TOTAL_PAGES(TOTAL_PAGES)
    ) u_table (
        .clk(clk),
        .rst_n(internal_rst_n),
        .wr_en(bt_wr_en),
        .wr_session_id(bt_wr_session),
        .wr_logical_page(bt_wr_logical),
        .wr_physical_page(bt_wr_physical),
        .rd_session_id(bt_rd_session),
        .rd_logical_page(bt_rd_logical),
        .rd_physical_page(bt_rd_physical),
        .rd_valid(bt_rd_valid),
        .inv_en(1'b0),
        .inv_session_id(3'd0),
        .inv_logical_page(5'd0)
    );

    rw_engine #(
        .NUM_SESSIONS(NUM_SESSIONS),
        .TOTAL_PAGES(TOTAL_PAGES),
        .PAGE_SIZE_TOKENS(PAGE_SIZE_TOKENS),
        .HEAD_DIM(HEAD_DIM),
        .DATA_WIDTH(DATA_WIDTH),
        .SRAM_BANKS(SRAM_BANKS)
    ) u_rw (
        .clk(clk),
        .rst_n(internal_rst_n),
        .wr_req(rw_wr_req),
        .wr_session_id(wr_sess_hold),
        .wr_token_pos(wr_token_hold),
        .wr_k_data(wr_k_hold),
        .wr_v_data(wr_v_hold),
        .wr_ack(rw_wr_ack),
        .rd_req(rw_rd_req),
        .rd_session_id(rd_session_id),
        .rd_token_start(rd_token_start),
        .rd_token_end(rd_token_end),
        .rd_k_data(rd_k_data),
        .rd_v_data(rd_v_data),
        .rd_valid(rd_valid),
        .rd_last(rd_last),
        .rd_busy(rd_busy),
        .bt_rd_session(bt_rd_session),
        .bt_rd_logical_page(bt_rd_logical),
        .bt_rd_physical_page(bt_rd_physical),
        .bt_rd_valid(bt_rd_valid),
        .sram_ce(sram_ce),
        .sram_we(sram_we),
        .sram_addr(sram_addr),
        .sram_wdata(sram_wdata),
        .sram_rdata(sram_rdata),
        .page_session_map(page_session_map),
        .scrub_req(scrub_req_w),
        .scrub_page_id(scrub_page_w),
        .scrub_done(scrub_done),
        .sec_fault(rw_sec_fault)
    );

    prefetch_ctrl #(
        .NUM_SESSIONS(NUM_SESSIONS),
        .PAGE_SIZE_TOKENS(PAGE_SIZE_TOKENS)
    ) u_prefetch (
        .clk(clk),
        .rst_n(internal_rst_n),
        .obs_session_id(rd_session_id),
        .obs_token_pos(rd_token_start),
        .obs_rd_req(rw_rd_req),
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
        .rst_n(internal_rst_n),
        .almost_full(almost_full),
        .lru_update_en(alloc_ack),
        .lru_update_page(alloc_page_id),
        .evict_valid(evict_valid),
        .evict_page_id(evict_page_id),
        .evict_session_id(evict_session_id),
        .evict_ack(evict_ack),
        .free_req(evict_free_req),
        .free_page_id(evict_free_page_id),
        .page_session_map(page_session_map)
    );

    // ------------------------------------------------------------------
    // SRAM banks
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (sram_ce[0]) begin
            if (sram_we[0]) begin
                sram_k_mem0[sram_addr[0]] <= sram_wdata[SRAM_WIDTH-1:KV_WIDTH];
                sram_v_mem0[sram_addr[0]] <= sram_wdata[KV_WIDTH-1:0];
            end
            sram_rdata[0] <= {sram_k_mem0[sram_addr[0]],
                              sram_v_mem0[sram_addr[0]]};
        end
        if (sram_ce[1]) begin
            if (sram_we[1]) begin
                sram_k_mem1[sram_addr[1]] <= sram_wdata[SRAM_WIDTH-1:KV_WIDTH];
                sram_v_mem1[sram_addr[1]] <= sram_wdata[KV_WIDTH-1:0];
            end
            sram_rdata[1] <= {sram_k_mem1[sram_addr[1]],
                              sram_v_mem1[sram_addr[1]]};
        end
        if (sram_ce[2]) begin
            if (sram_we[2]) begin
                sram_k_mem2[sram_addr[2]] <= sram_wdata[SRAM_WIDTH-1:KV_WIDTH];
                sram_v_mem2[sram_addr[2]] <= sram_wdata[KV_WIDTH-1:0];
            end
            sram_rdata[2] <= {sram_k_mem2[sram_addr[2]],
                              sram_v_mem2[sram_addr[2]]};
        end
        if (sram_ce[3]) begin
            if (sram_we[3]) begin
                sram_k_mem3[sram_addr[3]] <= sram_wdata[SRAM_WIDTH-1:KV_WIDTH];
                sram_v_mem3[sram_addr[3]] <= sram_wdata[KV_WIDTH-1:0];
            end
            sram_rdata[3] <= {sram_k_mem3[sram_addr[3]],
                              sram_v_mem3[sram_addr[3]]};
        end
    end

    // ------------------------------------------------------------------
    // Prefetch ack (one-cycle delay)
    // ------------------------------------------------------------------
    always @(posedge clk or negedge internal_rst_n) begin
        if (!internal_rst_n) begin
            pf_ack <= 1'b0;
        end else begin
            pf_ack <= pf_req;
        end
    end

    // ------------------------------------------------------------------
    // Security fault latch
    // Set on rw_engine sec_fault pulse; cleared only by reset.
    // ------------------------------------------------------------------
    always @(posedge clk or negedge internal_rst_n) begin
        if (!internal_rst_n) begin
            sec_fault_latch <= 1'b0;
        end else begin
            if (rw_sec_fault)
                sec_fault_latch <= 1'b1;
        end
    end

    // ------------------------------------------------------------------
    // Zero-on-free scrub FSM
    // Intercepts evict_free_req, triggers rw_engine scrub, then pulses
    // block_allocator.free_req only after scrub_done.
    // ------------------------------------------------------------------
    always @(posedge clk or negedge internal_rst_n) begin
        if (!internal_rst_n) begin
            scrub_state       <= SCRUB_IDLE;
            scrub_req_r       <= 1'b0;
            scrub_page_hold   <= 8'd0;
            alloc_free_req_r  <= 1'b0;
            alloc_free_page_r <= 8'd0;
        end else begin
            alloc_free_req_r <= 1'b0;

            case (scrub_state)
                SCRUB_IDLE: begin
                    scrub_req_r <= 1'b0;
                    if (evict_free_req) begin
                        scrub_page_hold <= evict_free_page_id;
                        scrub_req_r     <= 1'b1;
                        scrub_state     <= SCRUB_BUSY;
                    end
                end

                SCRUB_BUSY: begin
                    scrub_req_r <= 1'b1; // held until rw_engine accepts
                    if (scrub_done) begin
                        scrub_req_r      <= 1'b0;
                        alloc_free_req_r <= 1'b1;
                        alloc_free_page_r <= scrub_page_hold;
                        scrub_state      <= SCRUB_IDLE;
                    end
                end

                default: scrub_state <= SCRUB_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Write FSM + quota enforcement + page tracking
    // ------------------------------------------------------------------
    always @(posedge clk or negedge internal_rst_n) begin
        if (!internal_rst_n) begin
            wr_state              <= WR_IDLE;
            wr_ack                <= 1'b0;
            alloc_req             <= 1'b0;
            alloc_session_id      <= 3'd0;
            bt_wr_en              <= 1'b0;
            bt_wr_session         <= 3'd0;
            bt_wr_logical         <= 5'd0;
            bt_wr_physical        <= 8'd0;
            rw_wr_req             <= 1'b0;
            wr_sess_hold          <= 3'd0;
            wr_token_hold         <= 12'd0;
            wr_k_hold             <= {KV_WIDTH{1'b0}};
            wr_v_hold             <= {KV_WIDTH{1'b0}};
            wr_logical_hold       <= 5'd0;
            quota_exceeded_latch  <= 1'b0;
            for (i = 0; i < NUM_SESSIONS; i = i + 1) begin
                for (j = 0; j < 32; j = j + 1)
                    page_valid[i][j] <= 1'b0;
                pages_per_session[i] <= 8'd0;
            end
            for (i = 0; i < TOTAL_PAGES; i = i + 1)
                page_session_map[i] <= 3'd0;
        end else begin
            wr_ack    <= 1'b0;
            alloc_req <= 1'b0;
            bt_wr_en  <= 1'b0;
            rw_wr_req <= 1'b0;

            // Decrement session quota on eviction
            if (evict_free_req) begin
                if (pages_per_session[page_session_map[evict_free_page_id]] > 8'd0)
                    pages_per_session[page_session_map[evict_free_page_id]] <=
                        pages_per_session[page_session_map[evict_free_page_id]] - 1'b1;
                page_session_map[evict_free_page_id] <= 3'd0;
            end

            case (wr_state)
                WR_IDLE: begin
                    if (global_enable && wr_req && !wr_ack) begin
                        wr_sess_hold    <= wr_session_id;
                        wr_token_hold   <= wr_token_pos;
                        wr_k_hold       <= wr_k_data;
                        wr_v_hold       <= wr_v_data;
                        wr_logical_hold <= wr_logical_page;
                        if (page_valid[wr_session_id][wr_logical_page]) begin
                            wr_state <= WR_START_RW;
                        end else begin
                            // Quota check: 0 means unlimited
                            if (max_pages_per_session == 8'd0 ||
                                pages_per_session[wr_session_id] < max_pages_per_session) begin
                                alloc_session_id <= wr_session_id;
                                alloc_req        <= 1'b1;
                                wr_state         <= WR_ALLOC_WAIT;
                            end else begin
                                quota_exceeded_latch <= 1'b1;
                                wr_state             <= WR_IDLE; // drop write
                            end
                        end
                    end
                end

                WR_ALLOC_WAIT: begin
                    if (alloc_ack) begin
                        bt_wr_en       <= 1'b1;
                        bt_wr_session  <= wr_sess_hold;
                        bt_wr_logical  <= wr_logical_hold;
                        bt_wr_physical <= alloc_page_id;
                        page_valid[wr_sess_hold][wr_logical_hold] <= 1'b1;
                        page_session_map[alloc_page_id] <= wr_sess_hold;
                        pages_per_session[wr_sess_hold] <=
                            pages_per_session[wr_sess_hold] + 1'b1;
                        wr_state <= WR_TABLE_WAIT;
                    end
                end

                WR_TABLE_WAIT: begin
                    wr_state <= WR_START_RW;
                end

                WR_START_RW: begin
                    rw_wr_req <= 1'b1;
                    wr_state  <= WR_WAIT_RW;
                end

                WR_WAIT_RW: begin
                    if (rw_wr_ack) begin
                        wr_ack   <= 1'b1;
                        wr_state <= WR_IDLE;
                    end
                end

                default: begin
                    wr_state <= WR_IDLE;
                end
            endcase
        end
    end

endmodule
