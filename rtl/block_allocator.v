`timescale 1ns/1ps
// Paged KV Cache -- Block Allocator
// Circular FIFO free list backed by Artix-7 LUTRAM (distributed RAM).
// On reset, a 256-cycle init FSM fills every slot so alloc_ack fires
// exactly one cycle after alloc_req with no external init driver needed.

module block_allocator #(
    parameter TOTAL_PAGES = 256
) (
    input             clk,
    input             rst_n,

    // Alloc port -- response registered, valid one cycle after req
    input             alloc_req,
    input       [2:0] alloc_session_id,   // reserved for future tagging
    output reg        alloc_ack,
    output reg  [7:0] alloc_page_id,

    // Free port -- page returned on the same cycle as free_req
    input             free_req,
    input       [7:0] free_page_id,

    // Status
    output      [7:0] pages_free,         // saturates at 8'hFF when count==256
    output      [7:0] pages_used,
    output            almost_full         // asserted when pages_free <= 16
);

    // ----------------------------------------------------------------
    // LUTRAM free list
    // Vivado infers 256x8 distributed RAM from a reg array with
    // synchronous write and asynchronous read.  The attribute forces
    // the inference even when Vivado would otherwise choose BRAM.
    // No reset on the array -- LUTRAM has no synchronous reset.
    // ----------------------------------------------------------------
    (* ram_style = "distributed" *)
    reg [7:0] free_list [0:TOTAL_PAGES-1];

    // ----------------------------------------------------------------
    // Internal state
    // ----------------------------------------------------------------
    reg [7:0] head;       // FIFO read pointer (next page to allocate)
    reg [7:0] tail;       // FIFO write pointer (next slot for freed page)
    reg [8:0] count;      // free-page count, 0..256 (needs 9 bits)

    reg [7:0] init_cnt;   // init FSM counter
    reg       init_done;  // 1 after all 256 slots are written

    // Asynchronous LUTRAM read -- head declared above, no forward reference.
    wire [7:0] head_data = free_list[head];

    // ----------------------------------------------------------------
    // Derived outputs
    // ----------------------------------------------------------------
    assign pages_free  = count[8] ? 8'hFF : count[7:0];       // saturate: 256 -> 0xFF
    assign pages_used  = count[8] ? 8'h00 : (9'd256 - count); // 0 used when all free
    assign almost_full = init_done && (count <= 9'd16);

    // ----------------------------------------------------------------
    // LUTRAM write port -- synchronous, no reset
    // Priority: init beats free_req (init_done=0 implies not yet ready)
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (!init_done)
            free_list[init_cnt] <= init_cnt;   // fill slot i with page i
        else if (free_req)
            free_list[tail] <= free_page_id;
    end

    // ----------------------------------------------------------------
    // Control FSM
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_cnt      <= 8'd0;
            init_done     <= 1'b0;
            head          <= 8'd0;
            tail          <= 8'd0;
            count         <= 9'd0;
            alloc_ack     <= 1'b0;
            alloc_page_id <= 8'd0;

        end else if (!init_done) begin
            // Fill the LUTRAM over 256 cycles, then go live
            if (init_cnt == 8'd255) begin
                init_done <= 1'b1;
                count     <= 9'd256;   // all pages now in free list
                // head and tail remain 0 (correct FIFO start)
            end
            init_cnt  <= init_cnt + 1'b1;
            alloc_ack <= 1'b0;

        end else begin
            // ---- Normal operation ----
            alloc_ack <= 1'b0;

            // Count: handle simultaneous alloc+free (net zero)
            if (alloc_req && (count > 9'd0) && free_req)
                count <= count;                 // net 0
            else if (alloc_req && (count > 9'd0))
                count <= count - 1'b1;
            else if (free_req)
                count <= count + 1'b1;
                // Note: a double-free when count==256 would wrap to 257
                // (9-bit, defined behaviour) but is caller's responsibility.

            // Alloc -- register output; fires iff list is non-empty
            if (alloc_req && (count > 9'd0)) begin
                alloc_page_id <= head_data;
                alloc_ack     <= 1'b1;
                head          <= head + 1'b1;
            end

            // Free -- advance tail (LUTRAM write is in the other always block)
            if (free_req)
                tail <= tail + 1'b1;
        end
    end

endmodule

