// Functional coverage collector for Hera
//
// Goals:
//   - All 8 session IDs written to
//   - All 32 logical pages written (via token_pos page bucket)
//   - All AXI registers read and written
//   - SLVERR response observed (error path exercised)
//   - Evictions seen for each session
//   - IRQ raised
//   - Cross of session × page

class hera_coverage extends uvm_subscriber #(hera_kv_wr_seq_item);
    `uvm_component_utils(hera_coverage)

    // Additional analysis ports for AXI and eviction
    uvm_analysis_imp_axi_cov   #(hera_axi_seq_item,   hera_coverage) axi_cov_export;
    uvm_analysis_imp_evict_cov #(hera_evict_seq_item,  hera_coverage) evict_cov_export;

    // Sampled item handles
    hera_kv_wr_seq_item kv_wr_txn;
    hera_axi_seq_item   axi_txn;
    hera_evict_seq_item evict_txn;

    // ------------------------------------------------------------------
    covergroup cg_kv_write;
        cp_session: coverpoint kv_wr_txn.session_id { bins s[] = {[0:7]}; }
        cp_page: coverpoint kv_wr_txn.token_pos[8:4] { // bits[8:4] = logical page 0..31
            bins pages[] = {[0:31]};
        }
        cp_cross_sess_page: cross cp_session, cp_page;
    endgroup

    covergroup cg_axi;
        cp_addr: coverpoint axi_txn.addr[7:0] {
            bins ctrl        = {8'h00};
            bins session_cfg = {8'h04};
            bins page_cfg    = {8'h08};
            bins status      = {8'h10};
            bins evict_addr  = {8'h14};
            bins irq_mask    = {8'h18};
            bins lock_reg    = {8'h1C};
            bins ip_version  = {8'h20};
            bins ip_buildid  = {8'h24};
        }
        cp_kind:  coverpoint axi_txn.kind;
        cp_bresp: coverpoint axi_txn.bresp {
            bins okay   = {2'b00};
            bins slverr = {2'b10};
        }
        cp_cross_addr_kind: cross cp_addr, cp_kind;
    endgroup

    covergroup cg_eviction;
        cp_evict_sess: coverpoint evict_txn.session_id { bins s[] = {[0:7]}; }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_kv_write = new();
        cg_axi      = new();
        cg_eviction = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        axi_cov_export   = new("axi_cov_export",   this);
        evict_cov_export = new("evict_cov_export", this);
    endfunction

    // From uvm_subscriber — KV write coverage
    function void write(hera_kv_wr_seq_item t);
        kv_wr_txn = t;
        if (t.ack_received) cg_kv_write.sample();
    endfunction

    function void write_axi_cov(hera_axi_seq_item t);
        axi_txn = t;
        cg_axi.sample();
    endfunction

    function void write_evict_cov(hera_evict_seq_item t);
        evict_txn = t;
        cg_eviction.sample();
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf(
            "\n=== Coverage Report ===\n" +
            "  KV write (sess×page): %0.1f%%\n" +
            "  AXI register access : %0.1f%%\n" +
            "  Eviction session    : %0.1f%%",
            cg_kv_write.get_coverage(),
            cg_axi.get_coverage(),
            cg_eviction.get_coverage()), UVM_NONE)
    endfunction
endclass
