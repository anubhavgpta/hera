// Hera coverage collector
//
// NOTE: xsim 2018.2 does not support SystemVerilog covergroups.
// Coverage counting is done with plain integer counters so the environment
// compiles and runs under xsim. When migrating to Questa/Xcelium the
// covergroup bodies can be restored for proper functional coverage closure.

class hera_coverage extends uvm_subscriber #(hera_kv_wr_seq_item);
    `uvm_component_utils(hera_coverage)

    uvm_analysis_imp_axi_cov   #(hera_axi_seq_item,   hera_coverage) axi_cov_export;
    uvm_analysis_imp_evict_cov #(hera_evict_seq_item,  hera_coverage) evict_cov_export;

    // Counter-based coverage buckets (xsim workaround for missing covergroup support)
    int unsigned sess_wr_count [8];   // writes per session ID
    int unsigned page_wr_count [32];  // writes per logical page bucket (token[8:4])
    int unsigned axi_rd_count  [9];   // reads per register slot index
    int unsigned axi_wr_count  [9];   // writes per register slot index
    int unsigned slverr_count;        // SLVERR responses observed
    int unsigned evict_count   [8];   // evictions per session

    // Map register byte address to slot 0-8 (-1 = unmapped)
    function int reg_slot(logic [7:0] a);
        case (a)
            8'h00: return 0;  8'h04: return 1;  8'h08: return 2;
            8'h10: return 3;  8'h14: return 4;  8'h18: return 5;
            8'h1C: return 6;  8'h20: return 7;  8'h24: return 8;
            default: return -1;
        endcase
    endfunction

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        axi_cov_export   = new("axi_cov_export",   this);
        evict_cov_export = new("evict_cov_export", this);
    endfunction

    // From uvm_subscriber -- KV writes
    function void write(hera_kv_wr_seq_item t);
        if (!t.ack_received) return;
        sess_wr_count[int'(t.session_id)]++;
        page_wr_count[int'(t.token_pos[8:4])]++;
    endfunction

    function void write_axi_cov(hera_axi_seq_item t);
        int slot = reg_slot(t.addr[7:0]);
        if (slot < 0) return;
        if (t.kind == hera_axi_seq_item::AXI_READ) axi_rd_count[slot]++;
        else                                         axi_wr_count[slot]++;
        if (t.bresp == 2'b10) slverr_count++;
    endfunction

    function void write_evict_cov(hera_evict_seq_item t);
        evict_count[int'(t.session_id)]++;
    endfunction

    function void report_phase(uvm_phase phase);
        int sess_hit = 0, page_hit = 0, rd_hit = 0, wr_hit = 0;
        foreach (sess_wr_count[i]) if (sess_wr_count[i] > 0) sess_hit++;
        foreach (page_wr_count[i]) if (page_wr_count[i] > 0) page_hit++;
        foreach (axi_rd_count[i])  if (axi_rd_count[i]  > 0) rd_hit++;
        foreach (axi_wr_count[i])  if (axi_wr_count[i]  > 0) wr_hit++;
        `uvm_info("COV", $sformatf(
            "\n=== Coverage Summary (counter-based) ===\n  Sessions written      : %0d / 8\n  Logical pages touched : %0d / 32\n  AXI regs read         : %0d / 9\n  AXI regs written      : %0d / 9\n  SLVERR responses seen : %0d",
            sess_hit, page_hit, rd_hit, wr_hit, slverr_count), UVM_NONE)
    endfunction
endclass
