`timescale 1ns/1ps
// Hera -- Eviction Engine
//
// Tracks approximate per-page access frequency and scans all physical pages
// when memory is almost full.  The minimum counter page is reported to host
// software and freed after host acknowledgement.

module eviction_engine #(
    parameter NUM_SESSIONS = 8,
    parameter TOTAL_PAGES  = 256
) (
    input clk,
    input rst_n,

    // Trigger
    input almost_full,

    // LRU tracking inputs
    input        lru_update_en,
    input  [7:0] lru_update_page,

    // Eviction output to host
    output reg       evict_valid,
    output reg [7:0] evict_page_id,
    output reg [2:0] evict_session_id,

    // Host acknowledgement
    input evict_ack,

    // Post-eviction free request
    output reg       free_req,
    output reg [7:0] free_page_id,

    // Reverse page-to-session map
    input [2:0] page_session_map [255:0]
);

    localparam ST_IDLE         = 3'd0;
    localparam ST_SCAN         = 3'd1;
    localparam ST_EVICT_NOTIFY = 3'd2;
    localparam ST_WAIT_ACK     = 3'd3;
    localparam ST_FREE         = 3'd4;

    reg [2:0] state;
    reg [7:0] access_count [0:TOTAL_PAGES-1];
    reg [7:0] scan_idx;
    reg [7:0] min_count;
    reg [7:0] min_page;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            evict_valid      <= 1'b0;
            evict_page_id    <= 8'd0;
            evict_session_id <= 3'd0;
            free_req         <= 1'b0;
            free_page_id     <= 8'd0;
            scan_idx         <= 8'd0;
            min_count        <= 8'hFF;
            min_page         <= 8'd0;
            for (i = 0; i < TOTAL_PAGES; i = i + 1)
                access_count[i] <= 8'd0;
        end else begin
            free_req <= 1'b0;

            if (lru_update_en)
                access_count[lru_update_page] <= access_count[lru_update_page] +
                                                 1'b1;

            case (state)
                ST_IDLE: begin
                    evict_valid <= 1'b0;
                    if (almost_full) begin
                        scan_idx  <= 8'd0;
                        min_count <= 8'hFF;
                        min_page  <= 8'd0;
                        state     <= ST_SCAN;
                    end
                end

                ST_SCAN: begin
                    if (access_count[scan_idx] < min_count) begin
                        min_count <= access_count[scan_idx];
                        min_page  <= scan_idx;
                    end

                    if (scan_idx == 8'hFF)
                        state <= ST_EVICT_NOTIFY;
                    else
                        scan_idx <= scan_idx + 1'b1;
                end

                ST_EVICT_NOTIFY: begin
                    evict_page_id    <= min_page;
                    evict_session_id <= page_session_map[min_page];
                    evict_valid      <= 1'b1;
                    state            <= ST_WAIT_ACK;
                end

                ST_WAIT_ACK: begin
                    evict_valid <= 1'b1;
                    if (evict_ack)
                        state <= ST_FREE;
                end

                ST_FREE: begin
                    evict_valid  <= 1'b0;
                    free_req     <= 1'b1;
                    free_page_id <= evict_page_id;
                    state        <= ST_IDLE;
                end

                default: begin
                    state       <= ST_IDLE;
                    evict_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule
