`timescale 1ns/1ps
// Vera -- AXI4-Lite Host Control Interface
//
// Provides CPU-visible control, configuration, status, and IRQ registers.
// STATUS and EVICT_ADDR are live views of internal Vera status inputs.

module axi4_lite_if #(
    parameter NUM_SESSIONS = 8,
    parameter TOTAL_PAGES  = 256
) (
    input clk,
    input rst_n,

    // Write address channel
    input         s_axi_awvalid,
    output        s_axi_awready,
    input  [31:0] s_axi_awaddr,

    // Write data channel
    input         s_axi_wvalid,
    output        s_axi_wready,
    input  [31:0] s_axi_wdata,
    input  [3:0]  s_axi_wstrb,

    // Write response channel
    output reg        s_axi_bvalid,
    input             s_axi_bready,
    output      [1:0] s_axi_bresp,

    // Read address channel
    input         s_axi_arvalid,
    output        s_axi_arready,
    input  [31:0] s_axi_araddr,

    // Read data channel
    output reg        s_axi_rvalid,
    input             s_axi_rready,
    output reg [31:0] s_axi_rdata,
    output      [1:0] s_axi_rresp,

    // Internal status inputs
    input  [7:0] pages_free_i,
    input  [7:0] pages_used_i,
    input        almost_full_i,
    input        evict_pending_i,
    input  [7:0] evict_page_id_i,
    input  [2:0] evict_session_id_i,

    // Decoded control outputs
    output        global_enable,
    output reg    soft_reset,
    output [2:0]  active_session_id,
    output [7:0]  max_pages_per_session,
    output        irq
);

    localparam ADDR_CTRL        = 8'h00;
    localparam ADDR_SESSION_CFG = 8'h04;
    localparam ADDR_PAGE_CFG    = 8'h08;
    localparam ADDR_STATUS      = 8'h10;
    localparam ADDR_EVICT_ADDR  = 8'h14;
    localparam ADDR_IRQ_MASK    = 8'h18;

    reg [31:0] ctrl_reg;
    reg [31:0] session_cfg_reg;
    reg [31:0] page_cfg_reg;
    reg [31:0] irq_mask_reg;

    reg        aw_seen;
    reg [31:0] awaddr_hold;
    reg        w_seen;
    reg [31:0] wdata_hold;
    reg [3:0]  wstrb_hold;

    reg        rd_pending;
    reg [31:0] araddr_hold;

    wire aw_fire = s_axi_awvalid && s_axi_awready;
    wire w_fire  = s_axi_wvalid  && s_axi_wready;
    wire ar_fire = s_axi_arvalid && s_axi_arready;

    wire have_aw = aw_seen || aw_fire;
    wire have_w  = w_seen  || w_fire;
    wire do_write = have_aw && have_w && !s_axi_bvalid;

    wire [31:0] write_addr = aw_seen ? awaddr_hold : s_axi_awaddr;
    wire [31:0] write_data = w_seen  ? wdata_hold  : s_axi_wdata;
    wire [3:0]  write_strb = w_seen  ? wstrb_hold  : s_axi_wstrb;

    assign s_axi_awready = !aw_seen && !s_axi_bvalid;
    assign s_axi_wready  = !w_seen  && !s_axi_bvalid;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_arready = !rd_pending && !s_axi_rvalid;
    assign s_axi_rresp   = 2'b00;

    assign global_enable = ctrl_reg[0];
    assign active_session_id = session_cfg_reg[2:0];
    assign max_pages_per_session = page_cfg_reg[7:0];
    assign irq = (almost_full_i & ~irq_mask_reg[0]) |
                 (evict_pending_i & ~irq_mask_reg[1]);

    function [31:0] apply_wstrb;
        input [31:0] old_data;
        input [31:0] new_data;
        input [3:0]  strb;
        begin
            apply_wstrb = old_data;
            if (strb[0])
                apply_wstrb[7:0] = new_data[7:0];
            if (strb[1])
                apply_wstrb[15:8] = new_data[15:8];
            if (strb[2])
                apply_wstrb[23:16] = new_data[23:16];
            if (strb[3])
                apply_wstrb[31:24] = new_data[31:24];
        end
    endfunction

    function [31:0] reg_read_data;
        input [31:0] addr;
        begin
            case (addr[7:0])
                ADDR_CTRL:
                    reg_read_data = {30'd0, 1'b0, ctrl_reg[0]};
                ADDR_SESSION_CFG:
                    reg_read_data = {29'd0, session_cfg_reg[2:0]};
                ADDR_PAGE_CFG:
                    reg_read_data = {24'd0, page_cfg_reg[7:0]};
                ADDR_STATUS:
                    reg_read_data = {14'd0, evict_pending_i, almost_full_i,
                                     pages_used_i, pages_free_i};
                ADDR_EVICT_ADDR:
                    reg_read_data = {21'd0, evict_session_id_i,
                                     evict_page_id_i};
                ADDR_IRQ_MASK:
                    reg_read_data = {30'd0, irq_mask_reg[1:0]};
                default:
                    reg_read_data = 32'd0;
            endcase
        end
    endfunction

    reg [31:0] masked_write;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_reg        <= 32'd0;
            session_cfg_reg <= 32'd0;
            page_cfg_reg    <= 32'd0;
            irq_mask_reg    <= 32'd0;
            aw_seen         <= 1'b0;
            awaddr_hold     <= 32'd0;
            w_seen          <= 1'b0;
            wdata_hold      <= 32'd0;
            wstrb_hold      <= 4'd0;
            s_axi_bvalid    <= 1'b0;
            rd_pending      <= 1'b0;
            araddr_hold     <= 32'd0;
            s_axi_rvalid    <= 1'b0;
            s_axi_rdata     <= 32'd0;
            soft_reset      <= 1'b0;
        end else begin
            soft_reset <= 1'b0;

            if (aw_fire) begin
                aw_seen     <= 1'b1;
                awaddr_hold <= s_axi_awaddr;
            end

            if (w_fire) begin
                w_seen     <= 1'b1;
                wdata_hold <= s_axi_wdata;
                wstrb_hold <= s_axi_wstrb;
            end

            if (do_write) begin
                case (write_addr[7:0])
                    ADDR_CTRL: begin
                        masked_write = apply_wstrb(ctrl_reg, write_data,
                                                   write_strb);
                        ctrl_reg[0] <= masked_write[0];
                        if (masked_write[1])
                            soft_reset <= 1'b1;
                    end
                    ADDR_SESSION_CFG: begin
                        masked_write = apply_wstrb(session_cfg_reg, write_data,
                                                   write_strb);
                        session_cfg_reg[2:0] <= masked_write[2:0];
                    end
                    ADDR_PAGE_CFG: begin
                        masked_write = apply_wstrb(page_cfg_reg, write_data,
                                                   write_strb);
                        page_cfg_reg[7:0] <= masked_write[7:0];
                    end
                    ADDR_IRQ_MASK: begin
                        masked_write = apply_wstrb(irq_mask_reg, write_data,
                                                   write_strb);
                        irq_mask_reg[1:0] <= masked_write[1:0];
                    end
                    default: begin
                        // RO or unmapped write: OKAY response, no side effect.
                    end
                endcase
                aw_seen      <= 1'b0;
                w_seen       <= 1'b0;
                s_axi_bvalid <= 1'b1;
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (ar_fire) begin
                araddr_hold <= s_axi_araddr;
                rd_pending  <= 1'b1;
            end

            if (rd_pending) begin
                s_axi_rdata  <= reg_read_data(araddr_hold);
                s_axi_rvalid <= 1'b1;
                rd_pending   <= 1'b0;
            end else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
