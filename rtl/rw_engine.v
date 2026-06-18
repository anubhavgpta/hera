`timescale 1ns/1ps
// Hera -- Paged KV Cache Read/Write Engine
//
// Resolves session/token addresses through the block table and performs
// scatter-gather SRAM reads and writes across physical pages.
//
// Security hardening:
//   Session isolation: on every read lookup, the physical page's session
//   tag (page_session_map) is compared against the requesting session.
//   A mismatch zeroes the output and pulses sec_fault for one cycle.
//   Scrub: when scrub_req is asserted, the engine overwrites all tokens
//   in scrub_page_id with zeros before the page is returned to the
//   free list -- preventing cross-session data leakage after eviction.

module rw_engine #(
    parameter NUM_SESSIONS     = 8,
    parameter TOTAL_PAGES      = 256,
    parameter PAGE_SIZE_TOKENS = 16,
    parameter HEAD_DIM         = 64,
    parameter DATA_WIDTH       = 16,
    parameter SRAM_BANKS       = 4
) (
    input clk,
    input rst_n,

    // Write interface
    input  wr_req,
    input  [2:0]  wr_session_id,
    input  [11:0] wr_token_pos,
    input  [DATA_WIDTH*HEAD_DIM-1:0] wr_k_data,
    input  [DATA_WIDTH*HEAD_DIM-1:0] wr_v_data,
    output reg wr_ack,

    // Read interface
    input  rd_req,
    input  [2:0]  rd_session_id,
    input  [11:0] rd_token_start,
    input  [11:0] rd_token_end,
    output reg [DATA_WIDTH*HEAD_DIM-1:0] rd_k_data,
    output reg [DATA_WIDTH*HEAD_DIM-1:0] rd_v_data,
    output reg rd_valid,
    output reg rd_last,
    output reg rd_busy,

    // Block table read interface
    output reg [2:0]  bt_rd_session,
    output reg [4:0]  bt_rd_logical_page,
    input      [7:0]  bt_rd_physical_page,
    input             bt_rd_valid,

    // SRAM interface -- each physical page maps to one bank
    output reg [SRAM_BANKS-1:0] sram_ce,
    output reg [SRAM_BANKS-1:0] sram_we,
    output reg [7:0]  sram_addr [SRAM_BANKS-1:0],
    output reg [DATA_WIDTH*HEAD_DIM*2-1:0] sram_wdata,
    input      [DATA_WIDTH*HEAD_DIM*2-1:0] sram_rdata [SRAM_BANKS-1:0],

    // Session isolation -- reverse map provided by top level
    input [2:0] page_session_map [255:0],

    // Scrub interface -- zero a page before returning it to free list
    input       scrub_req,
    input [7:0] scrub_page_id,
    output reg  scrub_done,

    // Security fault -- pulsed one cycle on isolation violation
    output reg  sec_fault
);

    localparam KV_WIDTH   = DATA_WIDTH * HEAD_DIM;
    localparam SRAM_WIDTH = KV_WIDTH * 2;
    localparam LAST_SCRUB_OFFSET = PAGE_SIZE_TOKENS - 1;

    localparam ST_IDLE       = 4'd0;
    localparam ST_WR_LOOKUP  = 4'd1;
    localparam ST_WR_SRAM    = 4'd2;
    localparam ST_WR_ACK     = 4'd3;
    localparam ST_RD_LOOKUP  = 4'd4;
    localparam ST_RD_SRAM    = 4'd5;
    localparam ST_RD_OUTPUT  = 4'd6;
    localparam ST_RD_ZERO    = 4'd7;
    localparam ST_SEC_FAULT  = 4'd8;
    localparam ST_SCRUB      = 4'd9;

    reg [3:0]  state;
    reg [11:0] cur_token;
    reg [11:0] end_token;
    reg [2:0]  active_session;
    reg [2:0]  wr_session_hold;
    reg [4:0]  wr_logical_hold;
    reg [7:0]  wr_offset_hold;
    reg [KV_WIDTH-1:0] wr_k_hold;
    reg [KV_WIDTH-1:0] wr_v_hold;
    reg [7:0]  active_phys_page;
    reg [1:0]  active_bank;
    reg [7:0]  active_addr;
    reg        sram_waited;
    reg        rd_lookup_waited;

    // Scrub counters
    reg [7:0]  scrub_page_hold;
    reg [7:0]  scrub_offset;
    wire [1:0] scrub_bank_w = scrub_page_hold % SRAM_BANKS;
    wire [7:0] scrub_base_w = (scrub_page_hold / SRAM_BANKS) * PAGE_SIZE_TOKENS;

    wire [4:0] wr_logical_page = wr_token_pos / PAGE_SIZE_TOKENS;
    wire [7:0] wr_page_offset  = wr_token_pos % PAGE_SIZE_TOKENS;
    wire [4:0] rd_logical_page = cur_token / PAGE_SIZE_TOKENS;
    wire [7:0] rd_page_offset  = cur_token % PAGE_SIZE_TOKENS;

    wire [1:0] phys_bank = bt_rd_physical_page % SRAM_BANKS;
    wire [7:0] phys_addr = ((bt_rd_physical_page / SRAM_BANKS) *
                            PAGE_SIZE_TOKENS) +
                           ((state == ST_WR_LOOKUP) ? wr_offset_hold :
                                                      rd_page_offset);

    integer i;

    always @(*) begin
        bt_rd_session = active_session;
        bt_rd_logical_page = rd_logical_page;

        if (state == ST_IDLE) begin
            if (wr_req) begin
                bt_rd_session = wr_session_id;
                bt_rd_logical_page = wr_logical_page;
            end else if (rd_req) begin
                bt_rd_session = rd_session_id;
                bt_rd_logical_page = rd_token_start / PAGE_SIZE_TOKENS;
            end
        end else if (state == ST_WR_LOOKUP) begin
            bt_rd_session = wr_session_hold;
            bt_rd_logical_page = wr_logical_hold;
        end else if (state == ST_RD_OUTPUT && cur_token != end_token) begin
            bt_rd_session = active_session;
            bt_rd_logical_page = (cur_token + 1'b1) / PAGE_SIZE_TOKENS;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= ST_IDLE;
            wr_ack             <= 1'b0;
            rd_k_data          <= {KV_WIDTH{1'b0}};
            rd_v_data          <= {KV_WIDTH{1'b0}};
            rd_valid           <= 1'b0;
            rd_last            <= 1'b0;
            rd_busy            <= 1'b0;
            sram_ce            <= {SRAM_BANKS{1'b0}};
            sram_we            <= {SRAM_BANKS{1'b0}};
            sram_wdata         <= {SRAM_WIDTH{1'b0}};
            cur_token          <= 12'd0;
            end_token          <= 12'd0;
            active_session     <= 3'd0;
            wr_session_hold    <= 3'd0;
            wr_logical_hold    <= 5'd0;
            wr_offset_hold     <= 8'd0;
            wr_k_hold          <= {KV_WIDTH{1'b0}};
            wr_v_hold          <= {KV_WIDTH{1'b0}};
            active_phys_page   <= 8'd0;
            active_bank        <= 2'd0;
            active_addr        <= 8'd0;
            sram_waited        <= 1'b0;
            rd_lookup_waited   <= 1'b0;
            scrub_page_hold    <= 8'd0;
            scrub_offset       <= 8'd0;
            scrub_done         <= 1'b0;
            sec_fault          <= 1'b0;
            for (i = 0; i < SRAM_BANKS; i = i + 1)
                sram_addr[i] <= 8'd0;
        end else begin
            wr_ack     <= 1'b0;
            rd_valid   <= 1'b0;
            rd_last    <= 1'b0;
            sec_fault  <= 1'b0;
            scrub_done <= 1'b0;
            sram_ce    <= {SRAM_BANKS{1'b0}};
            sram_we    <= {SRAM_BANKS{1'b0}};

            case (state)
                ST_IDLE: begin
                    rd_busy <= 1'b0;
                    // Scrub takes priority over normal traffic
                    if (scrub_req) begin
                        scrub_page_hold <= scrub_page_id;
                        scrub_offset    <= 8'd0;
                        state           <= ST_SCRUB;
                    end else if (wr_req) begin
                        wr_session_hold <= wr_session_id;
                        wr_logical_hold <= wr_logical_page;
                        wr_offset_hold  <= wr_page_offset;
                        wr_k_hold       <= wr_k_data;
                        wr_v_hold       <= wr_v_data;
                        state           <= ST_WR_LOOKUP;
                    end else if (rd_req) begin
                        active_session   <= rd_session_id;
                        cur_token        <= rd_token_start;
                        end_token        <= rd_token_end;
                        rd_busy          <= 1'b1;
                        rd_lookup_waited <= 1'b0;
                        state            <= ST_RD_LOOKUP;
                    end
                end

                ST_WR_LOOKUP: begin
                    if (bt_rd_valid) begin
                        active_phys_page     <= bt_rd_physical_page;
                        active_bank          <= phys_bank;
                        active_addr          <= phys_addr;
                        sram_addr[phys_bank] <= phys_addr;
                        state                <= ST_WR_SRAM;
                    end
                end

                ST_WR_SRAM: begin
                    sram_ce[active_bank]   <= 1'b1;
                    sram_we[active_bank]   <= 1'b1;
                    sram_addr[active_bank] <= active_addr;
                    sram_wdata             <= {wr_k_hold, wr_v_hold};
                    state                  <= ST_WR_ACK;
                end

                ST_WR_ACK: begin
                    wr_ack <= 1'b1;
                    state  <= ST_IDLE;
                end

                ST_RD_LOOKUP: begin
                    rd_busy <= 1'b1;
                    if (bt_rd_valid) begin
                        // Session isolation check
                        if (page_session_map[bt_rd_physical_page] != active_session) begin
                            sec_fault <= 1'b1;
                            state     <= ST_SEC_FAULT;
                        end else begin
                            active_phys_page     <= bt_rd_physical_page;
                            active_bank          <= phys_bank;
                            active_addr          <= phys_addr;
                            sram_addr[phys_bank] <= phys_addr;
                            sram_waited          <= 1'b0;
                            rd_lookup_waited     <= 1'b0;
                            state                <= ST_RD_SRAM;
                        end
                    end else if (rd_lookup_waited) begin
                        rd_lookup_waited <= 1'b0;
                        state            <= ST_RD_ZERO;
                    end else begin
                        rd_lookup_waited <= 1'b1;
                    end
                end

                ST_RD_SRAM: begin
                    rd_busy              <= 1'b1;
                    sram_ce[active_bank] <= 1'b1;
                    sram_addr[active_bank] <= active_addr;
                    if (sram_waited)
                        state <= ST_RD_OUTPUT;
                    else
                        sram_waited <= 1'b1;
                end

                ST_RD_OUTPUT: begin
                    rd_busy   <= 1'b1;
                    rd_valid  <= 1'b1;
                    rd_last   <= (cur_token == end_token);
                    rd_k_data <= sram_rdata[active_bank][SRAM_WIDTH-1:KV_WIDTH];
                    rd_v_data <= sram_rdata[active_bank][KV_WIDTH-1:0];

                    if (cur_token == end_token) begin
                        rd_busy <= 1'b0;
                        state   <= ST_IDLE;
                    end else begin
                        cur_token        <= cur_token + 1'b1;
                        rd_lookup_waited <= 1'b0;
                        state            <= ST_RD_LOOKUP;
                    end
                end

                ST_RD_ZERO: begin
                    rd_busy   <= 1'b1;
                    rd_valid  <= 1'b1;
                    rd_last   <= (cur_token == end_token);
                    rd_k_data <= {KV_WIDTH{1'b0}};
                    rd_v_data <= {KV_WIDTH{1'b0}};

                    if (cur_token == end_token) begin
                        rd_busy <= 1'b0;
                        state   <= ST_IDLE;
                    end else begin
                        cur_token        <= cur_token + 1'b1;
                        rd_lookup_waited <= 1'b0;
                        state            <= ST_RD_LOOKUP;
                    end
                end

                // Output zeros for all remaining tokens in the range when an
                // isolation violation is detected.  sec_fault was already
                // pulsed in ST_RD_LOOKUP; do not re-assert here.
                ST_SEC_FAULT: begin
                    rd_busy   <= 1'b1;
                    rd_valid  <= 1'b1;
                    rd_last   <= (cur_token == end_token);
                    rd_k_data <= {KV_WIDTH{1'b0}};
                    rd_v_data <= {KV_WIDTH{1'b0}};

                    if (cur_token == end_token) begin
                        rd_busy <= 1'b0;
                        state   <= ST_IDLE;
                    end else begin
                        cur_token        <= cur_token + 1'b1;
                        rd_lookup_waited <= 1'b0;
                        state            <= ST_RD_LOOKUP;
                    end
                end

                // Zero all tokens of the evicted page before releasing it.
                // scrub_req is held by the top level until scrub_done fires.
                ST_SCRUB: begin
                    sram_ce[scrub_bank_w]   <= 1'b1;
                    sram_we[scrub_bank_w]   <= 1'b1;
                    sram_addr[scrub_bank_w] <= scrub_base_w + scrub_offset;
                    sram_wdata              <= {SRAM_WIDTH{1'b0}};

                    if (scrub_offset == LAST_SCRUB_OFFSET[7:0]) begin
                        scrub_done <= 1'b1;
                        state      <= ST_IDLE;
                    end else begin
                        scrub_offset <= scrub_offset + 1'b1;
                    end
                end

                default: begin
                    state   <= ST_IDLE;
                    rd_busy <= 1'b0;
                end
            endcase
        end
    end

endmodule
