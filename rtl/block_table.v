`timescale 1ns/1ps
// Hera -- Logical-to-Physical Page Mapping Table
//
// Address space: {session_id[2:0], logical_page[4:0]} ??' 8-bit flat index.
// page_data  : LUTRAM (distributed RAM, no reset -- valid bit gates all reads).
// valid_bits : 256-bit packed FF register (supports async reset).
//
// Write-first semantics implemented via combinational forwarding mux so that
// a simultaneous wr and rd to the same address return the written value from
// the registered output one cycle later, independent of NBA ordering.

module block_table #(
    parameter NUM_SESSIONS  = 8,
    parameter LOGICAL_PAGES = 32,
    parameter TOTAL_PAGES   = 256
) (
    input             clk,
    input             rst_n,

    // Write port
    input             wr_en,
    input       [2:0] wr_session_id,
    input       [4:0] wr_logical_page,
    input       [7:0] wr_physical_page,

    // Read port -- registered output, 1-cycle latency
    input       [2:0] rd_session_id,
    input       [4:0] rd_logical_page,
    output reg  [7:0] rd_physical_page,
    output reg        rd_valid,

    // Invalidation port
    input             inv_en,
    input       [2:0] inv_session_id,
    input       [4:0] inv_logical_page
);

    localparam DEPTH = NUM_SESSIONS * LOGICAL_PAGES; // 256

    // Flat 8-bit addresses
    wire [7:0] wr_addr  = {wr_session_id,  wr_logical_page};
    wire [7:0] rd_addr  = {rd_session_id,  rd_logical_page};
    wire [7:0] inv_addr = {inv_session_id, inv_logical_page};

    // ----------------------------------------------------------------
    // LUTRAM -- physical page IDs (256 ?-- 8 bits, distributed RAM)
    // Synchronous write, asynchronous read.  No reset -- the valid bit
    // gate ensures stale data is never observed.
    // ----------------------------------------------------------------
    (* ram_style = "distributed" *)
    reg [7:0] page_data [0:DEPTH-1];

    always @(posedge clk) begin
        if (wr_en)
            page_data[wr_addr] <= wr_physical_page;
    end

    // Asynchronous LUTRAM read
    wire [7:0] data_raw = page_data[rd_addr];

    // ----------------------------------------------------------------
    // Valid bits -- 256-bit packed FF register (not LUTRAM; supports reset)
    // ----------------------------------------------------------------
    reg [DEPTH-1:0] valid_bits;

    wire valid_raw = valid_bits[rd_addr];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_bits <= {DEPTH{1'b0}};
        end else begin
            if (wr_en)
                valid_bits[wr_addr]  <= 1'b1;
            // wr_en takes priority: suppress inv if it hits the same slot
            if (inv_en && !(wr_en && (wr_addr == inv_addr)))
                valid_bits[inv_addr] <= 1'b0;
        end
    end

    // ----------------------------------------------------------------
    // Write-first forwarding mux
    // When wr and rd target the same address in the same cycle, bypass
    // the LUTRAM so the registered output reflects the written value.
    // inv_rd_col clears rd_valid for a same-cycle invalidate+read.
    // wr_en wins over inv_en on collision (same priority as valid_bits).
    // ----------------------------------------------------------------
    wire wr_rd_col  = wr_en  && (wr_addr  == rd_addr);
    wire inv_rd_col = inv_en && (inv_addr == rd_addr);

    wire [7:0] data_next  = wr_rd_col ? wr_physical_page : data_raw;
    wire       valid_next = wr_rd_col  ? 1'b1 :
                            inv_rd_col ? 1'b0 :
                            valid_raw;

    // ----------------------------------------------------------------
    // Registered read output (1-cycle latency)
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_physical_page <= 8'd0;
            rd_valid         <= 1'b0;
        end else begin
            rd_physical_page <= data_next;
            rd_valid         <= valid_next;
        end
    end

endmodule

