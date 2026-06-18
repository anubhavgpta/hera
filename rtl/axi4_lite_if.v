`timescale 1ns/1ps
// Hera -- AXI4-Lite Host Control Interface
//
// Provides CPU-visible control, configuration, status, and IRQ registers.
// STATUS and EVICT_ADDR are live views of internal Hera status inputs.
//
// Security hardening:
//   SLVERR returned on writes to RO registers, unmapped addresses, and any
//   config write when LOCK[0] is set.
//   LOCK is sticky -- survives soft_reset, cleared only by hard rst_n.
//   IP_VERSION encodes the "HERA" watermark (0x48455241) in silicon.

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
    output     [1:0]  s_axi_bresp,

    // Read address channel
    input         s_axi_arvalid,
    output        s_axi_arready,
    input  [31:0] s_axi_araddr,

    // Read data channel
    output reg        s_axi_rvalid,
    input             s_axi_rready,
    output reg [31:0] s_axi_rdata,
    output     [1:0]  s_axi_rresp,

    // Internal status inputs
    input  [7:0] pages_free_i,
    input  [7:0] pages_used_i,
    input        almost_full_i,
    input        evict_pending_i,
    input  [7:0] evict_page_id_i,
    input  [2:0] evict_session_id_i,
    input        quota_exceeded_i,
    input        sec_fault_i,

    // Decoded control outputs
    output        global_enable,
    output reg    soft_reset,
    output [2:0]  active_session_id,
    output [7:0]  max_pages_per_session,
    output        irq
);

    // ----------------------------------------------------------------
    // Register map
    // ----------------------------------------------------------------
    localparam ADDR_CTRL        = 8'h00; // RW  (locked by LOCK[0])
    localparam ADDR_SESSION_CFG = 8'h04; // RW  (locked by LOCK[0])
    localparam ADDR_PAGE_CFG    = 8'h08; // RW  (locked by LOCK[0])
    localparam ADDR_STATUS      = 8'h10; // RO  -- SLVERR on write
    localparam ADDR_EVICT_ADDR  = 8'h14; // RO  -- SLVERR on write
    localparam ADDR_IRQ_MASK    = 8'h18; // RW
    localparam ADDR_LOCK        = 8'h1C; // RW  sticky write-once
    localparam ADDR_IP_VERSION  = 8'h20; // RO  silicon watermark
    localparam ADDR_IP_BUILDID  = 8'h24; // RO  build identifier

    // Silicon watermark -- "HERA" encoded as 4 ASCII bytes
    localparam [31:0] HERA_IP_VERSION = 32'h48455241;
    localparam [31:0] HERA_IP_BUILDID = 32'h00000001;

    // ----------------------------------------------------------------
    // Register storage
    // ----------------------------------------------------------------
    reg [31:0] ctrl_reg;
    reg [31:0] session_cfg_reg;
    reg [31:0] page_cfg_reg;
    reg [31:0] irq_mask_reg;
    reg        lock_reg;       // sticky, only cleared by hard rst_n

    // ----------------------------------------------------------------
    // AXI handshake state
    // ----------------------------------------------------------------
    reg        aw_seen;
    reg [31:0] awaddr_hold;
    reg        w_seen;
    reg [31:0] wdata_hold;
    reg [3:0]  wstrb_hold;

    reg        rd_pending;
    reg [31:0] araddr_hold;

    reg [1:0]  bresp_r;
    assign s_axi_bresp = bresp_r;
    assign s_axi_rresp = 2'b00;

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
    assign s_axi_arready = !rd_pending && !s_axi_rvalid;

    // ----------------------------------------------------------------
    // Control outputs
    // ----------------------------------------------------------------
    assign global_enable        = ctrl_reg[0];
    assign active_session_id    = session_cfg_reg[2:0];
    assign max_pages_per_session = page_cfg_reg[7:0];

    assign irq = (almost_full_i    & ~irq_mask_reg[0]) |
                 (evict_pending_i  & ~irq_mask_reg[1]) |
                 (quota_exceeded_i & ~irq_mask_reg[2]) |
                 (sec_fault_i      & ~irq_mask_reg[3]);

    // ----------------------------------------------------------------
    // Write access classification
    // ----------------------------------------------------------------
    wire write_is_ro =
        (write_addr[7:0] == ADDR_STATUS)     ||
        (write_addr[7:0] == ADDR_EVICT_ADDR) ||
        (write_addr[7:0] == ADDR_IP_VERSION) ||
        (write_addr[7:0] == ADDR_IP_BUILDID);

    wire write_is_config_locked = lock_reg && (
        (write_addr[7:0] == ADDR_CTRL)        ||
        (write_addr[7:0] == ADDR_SESSION_CFG) ||
        (write_addr[7:0] == ADDR_PAGE_CFG));

    wire write_is_mapped =
        (write_addr[7:0] == ADDR_CTRL)        ||
        (write_addr[7:0] == ADDR_SESSION_CFG) ||
        (write_addr[7:0] == ADDR_PAGE_CFG)    ||
        (write_addr[7:0] == ADDR_STATUS)      ||
        (write_addr[7:0] == ADDR_EVICT_ADDR)  ||
        (write_addr[7:0] == ADDR_IRQ_MASK)    ||
        (write_addr[7:0] == ADDR_LOCK)        ||
        (write_addr[7:0] == ADDR_IP_VERSION)  ||
        (write_addr[7:0] == ADDR_IP_BUILDID);

    wire write_is_error = write_is_ro || write_is_config_locked || !write_is_mapped;

    // ----------------------------------------------------------------
    // Utility: apply byte strobes
    // ----------------------------------------------------------------
    function [31:0] apply_wstrb;
        input [31:0] old_data;
        input [31:0] new_data;
        input [3:0]  strb;
        begin
            apply_wstrb = old_data;
            if (strb[0]) apply_wstrb[7:0]   = new_data[7:0];
            if (strb[1]) apply_wstrb[15:8]  = new_data[15:8];
            if (strb[2]) apply_wstrb[23:16] = new_data[23:16];
            if (strb[3]) apply_wstrb[31:24] = new_data[31:24];
        end
    endfunction

    // ----------------------------------------------------------------
    // Register read mux
    // ----------------------------------------------------------------
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
                    reg_read_data = {12'd0, sec_fault_i, quota_exceeded_i,
                                     evict_pending_i, almost_full_i,
                                     pages_used_i, pages_free_i};
                ADDR_EVICT_ADDR:
                    reg_read_data = {21'd0, evict_session_id_i, evict_page_id_i};
                ADDR_IRQ_MASK:
                    reg_read_data = {28'd0, irq_mask_reg[3:0]};
                ADDR_LOCK:
                    reg_read_data = {31'd0, lock_reg};
                ADDR_IP_VERSION:
                    reg_read_data = HERA_IP_VERSION;
                ADDR_IP_BUILDID:
                    reg_read_data = HERA_IP_BUILDID;
                default:
                    reg_read_data = 32'd0;
            endcase
        end
    endfunction

    reg [31:0] masked_write;

    // ----------------------------------------------------------------
    // LOCK register -- sticky, cleared only by hard rst_n
    // ----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lock_reg <= 1'b0;
        end else begin
            if (do_write && !write_is_error &&
                (write_addr[7:0] == ADDR_LOCK))
                lock_reg <= lock_reg | write_data[0]; // sticky
        end
    end

    // ----------------------------------------------------------------
    // Main register file and AXI state
    // ----------------------------------------------------------------
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
            bresp_r         <= 2'b00;
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
                bresp_r <= write_is_error ? 2'b10 : 2'b00;

                if (!write_is_error) begin
                    case (write_addr[7:0])
                        ADDR_CTRL: begin
                            masked_write = apply_wstrb(ctrl_reg, write_data,
                                                       write_strb);
                            ctrl_reg[0] <= masked_write[0];
                            if (masked_write[1])
                                soft_reset <= 1'b1;
                        end
                        ADDR_SESSION_CFG: begin
                            masked_write = apply_wstrb(session_cfg_reg,
                                                       write_data, write_strb);
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
                            irq_mask_reg[3:0] <= masked_write[3:0];
                        end
                        default: begin end
                    endcase
                end

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
