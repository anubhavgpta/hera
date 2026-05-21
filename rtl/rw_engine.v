`timescale 1ns/1ps
// Vera -- Paged KV Cache Read/Write Engine
//
// Resolves session/token addresses through the block table and performs
// scatter-gather SRAM reads and writes across physical pages.  The SRAM data
// word stores K and V together as {K, V}; read outputs split the same layout.

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

    // SRAM interface.  Each physical page maps to one bank.
    output reg [SRAM_BANKS-1:0] sram_ce,
    output reg [SRAM_BANKS-1:0] sram_we,
    output reg [7:0]  sram_addr [SRAM_BANKS-1:0],
    output reg [DATA_WIDTH*HEAD_DIM*2-1:0] sram_wdata,
    input      [DATA_WIDTH*HEAD_DIM*2-1:0] sram_rdata [SRAM_BANKS-1:0]
);

    localparam KV_WIDTH = DATA_WIDTH * HEAD_DIM;
    localparam SRAM_WIDTH = KV_WIDTH * 2;

    localparam ST_IDLE       = 3'd0;
    localparam ST_WR_LOOKUP  = 3'd1;
    localparam ST_WR_SRAM    = 3'd2;
    localparam ST_WR_ACK     = 3'd3;
    localparam ST_RD_LOOKUP  = 3'd4;
    localparam ST_RD_SRAM    = 3'd5;
    localparam ST_RD_OUTPUT  = 3'd6;

    reg [2:0]  state;
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
            for (i = 0; i < SRAM_BANKS; i = i + 1)
                sram_addr[i] <= 8'd0;
        end else begin
            wr_ack   <= 1'b0;
            rd_valid <= 1'b0;
            rd_last  <= 1'b0;
            sram_ce  <= {SRAM_BANKS{1'b0}};
            sram_we  <= {SRAM_BANKS{1'b0}};

            case (state)
                ST_IDLE: begin
                    rd_busy <= 1'b0;
                    if (wr_req) begin
                        wr_session_hold <= wr_session_id;
                        wr_logical_hold <= wr_logical_page;
                        wr_offset_hold  <= wr_page_offset;
                        wr_k_hold       <= wr_k_data;
                        wr_v_hold       <= wr_v_data;
                        state              <= ST_WR_LOOKUP;
                    end else if (rd_req) begin
                        active_session     <= rd_session_id;
                        cur_token          <= rd_token_start;
                        end_token          <= rd_token_end;
                        rd_busy            <= 1'b1;
                        state              <= ST_RD_LOOKUP;
                    end
                end

                ST_WR_LOOKUP: begin
                    if (bt_rd_valid) begin
                        active_phys_page <= bt_rd_physical_page;
                        active_bank      <= phys_bank;
                        active_addr      <= phys_addr;
                        sram_addr[phys_bank] <= phys_addr;
                        state            <= ST_WR_SRAM;
                    end
                end

                ST_WR_SRAM: begin
                    sram_ce[active_bank] <= 1'b1;
                    sram_we[active_bank] <= 1'b1;
                    sram_addr[active_bank] <= active_addr;
                    sram_wdata <= {wr_k_hold, wr_v_hold};
                    state <= ST_WR_ACK;
                end

                ST_WR_ACK: begin
                    wr_ack <= 1'b1;
                    state  <= ST_IDLE;
                end

                ST_RD_LOOKUP: begin
                    rd_busy <= 1'b1;
                    if (bt_rd_valid) begin
                        active_phys_page <= bt_rd_physical_page;
                        active_bank      <= phys_bank;
                        active_addr      <= phys_addr;
                        sram_addr[phys_bank] <= phys_addr;
                        sram_waited     <= 1'b0;
                        state            <= ST_RD_SRAM;
                    end
                end

                ST_RD_SRAM: begin
                    rd_busy <= 1'b1;
                    sram_ce[active_bank] <= 1'b1;
                    sram_addr[active_bank] <= active_addr;
                    if (sram_waited)
                        state <= ST_RD_OUTPUT;
                    else
                        sram_waited <= 1'b1;
                end

                ST_RD_OUTPUT: begin
                    rd_busy  <= 1'b1;
                    rd_valid <= 1'b1;
                    rd_last  <= (cur_token == end_token);
                    rd_k_data <= sram_rdata[active_bank][SRAM_WIDTH-1:KV_WIDTH];
                    rd_v_data <= sram_rdata[active_bank][KV_WIDTH-1:0];

                    if (cur_token == end_token) begin
                        rd_busy <= 1'b0;
                        state   <= ST_IDLE;
                    end else begin
                        cur_token <= cur_token + 1'b1;
                        state              <= ST_RD_LOOKUP;
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
