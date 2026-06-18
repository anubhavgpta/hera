// Hera UVM package — compiles all classes in dependency order.
// Include this file after compiling the four interface files.

package hera_uvm_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ----------------------------------------------------------------
    // Design constants (must match kv_cache_ctrl parameters)
    // ----------------------------------------------------------------
    localparam int KV_WIDTH          = 1024; // DATA_WIDTH(16) * HEAD_DIM(64)
    localparam int HERA_NUM_SESSIONS = 8;
    localparam int HERA_TOTAL_PAGES  = 256;

    // AXI register addresses
    localparam logic [31:0] HERA_ADDR_CTRL        = 32'h00;
    localparam logic [31:0] HERA_ADDR_SESSION_CFG = 32'h04;
    localparam logic [31:0] HERA_ADDR_PAGE_CFG    = 32'h08;
    localparam logic [31:0] HERA_ADDR_STATUS      = 32'h10;
    localparam logic [31:0] HERA_ADDR_EVICT_ADDR  = 32'h14;
    localparam logic [31:0] HERA_ADDR_IRQ_MASK    = 32'h18;
    localparam logic [31:0] HERA_ADDR_LOCK        = 32'h1C;
    localparam logic [31:0] HERA_ADDR_IP_VERSION  = 32'h20;
    localparam logic [31:0] HERA_ADDR_IP_BUILDID  = 32'h24;

    // ----------------------------------------------------------------
    // Tagged analysis imp declarations (must precede scoreboard/coverage)
    // ----------------------------------------------------------------
    `uvm_analysis_imp_decl(_axi)
    `uvm_analysis_imp_decl(_wr)
    `uvm_analysis_imp_decl(_rd)
    `uvm_analysis_imp_decl(_evict)
    `uvm_analysis_imp_decl(_axi_cov)
    `uvm_analysis_imp_decl(_evict_cov)

    // ----------------------------------------------------------------
    // Agents
    // ----------------------------------------------------------------
    `include "agents/hera_axi_seq_item.sv"
    `include "agents/hera_axi_driver.sv"
    `include "agents/hera_axi_monitor.sv"
    `include "agents/hera_axi_agent.sv"

    `include "agents/hera_kv_wr_seq_item.sv"
    `include "agents/hera_kv_wr_driver.sv"
    `include "agents/hera_kv_wr_monitor.sv"
    `include "agents/hera_kv_wr_agent.sv"

    `include "agents/hera_kv_rd_seq_item.sv"
    `include "agents/hera_kv_rd_driver.sv"
    `include "agents/hera_kv_rd_monitor.sv"
    `include "agents/hera_kv_rd_agent.sv"

    `include "agents/hera_evict_seq_item.sv"
    `include "agents/hera_evict_driver.sv"
    `include "agents/hera_evict_monitor.sv"
    `include "agents/hera_evict_agent.sv"

    // ----------------------------------------------------------------
    // Environment
    // ----------------------------------------------------------------
    `include "env/hera_scoreboard.sv"
    `include "env/hera_coverage.sv"
    `include "env/hera_env.sv"

    // ----------------------------------------------------------------
    // Sequences (order: primitives -> virtual sequencer -> vseqs -> tests)
    // ----------------------------------------------------------------
    `include "sequences/hera_axi_sequences.sv"
    `include "sequences/hera_kv_sequences.sv"
    `include "sequences/hera_virtual_sequencer.sv"
    `include "sequences/hera_virtual_sequences.sv"

    // ----------------------------------------------------------------
    // Tests
    // ----------------------------------------------------------------
    `include "tests/hera_base_test.sv"
    `include "tests/hera_smoke_test.sv"
    `include "tests/hera_stress_test.sv"
    `include "tests/hera_security_test.sv"
    `include "tests/hera_soft_reset_test.sv"

endpackage
