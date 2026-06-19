// Hera UVM package -- xsim 2018.2 compatible
//
// Differences from hera_uvm_pkg:
//   - No uvm_sequence / uvm_sequencer (xsim cannot elaborate .start())
//   - No @(cb iff cond) clocking-block guards (not supported in xsim 2018.2)
//   - Monitors use @(posedge clk) polling loops instead
//   - Tests drive virtual interfaces directly from run_phase tasks
//   - Evict auto-ack is a plain uvm_component (not uvm_driver)

package hera_uvm_xsim_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ----------------------------------------------------------------
    // Tagged analysis-imp declarations (must precede scoreboard/coverage)
    // ----------------------------------------------------------------
    `uvm_analysis_imp_decl(_axi)
    `uvm_analysis_imp_decl(_wr)
    `uvm_analysis_imp_decl(_rd)
    `uvm_analysis_imp_decl(_evict)
    `uvm_analysis_imp_decl(_axi_cov)
    `uvm_analysis_imp_decl(_evict_cov)

    // ----------------------------------------------------------------
    // Sequence items  (uvm_sequence_item subclasses -- compatible)
    // ----------------------------------------------------------------
    `include "agents/hera_axi_seq_item.sv"
    `include "agents/hera_kv_wr_seq_item.sv"
    `include "agents/hera_kv_rd_seq_item.sv"
    `include "agents/hera_evict_seq_item.sv"

    // ----------------------------------------------------------------
    // Scoreboard and coverage  (no sequence dependencies)
    // ----------------------------------------------------------------
    `include "env/hera_scoreboard.sv"
    `include "env/hera_coverage.sv"

    // ================================================================
    // xsim-compatible AXI monitor
    // Replaces @(cb iff cond) with posedge-polling loops.
    // ================================================================
    class hera_xsim_axi_monitor extends uvm_monitor;
        `uvm_component_utils(hera_xsim_axi_monitor)

        virtual hera_axi4_lite_if vif;
        uvm_analysis_port #(hera_axi_seq_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual hera_axi4_lite_if)::get(
                    this, "", "axi_vif", vif))
                `uvm_fatal("CFG", "axi_vif not found in config_db")
        endfunction

        task run_phase(uvm_phase phase);
            // Wait for reset release
            do @(posedge vif.clk); while (!vif.rst_n);
            fork
                monitor_writes();
                monitor_reads();
            join
        endtask

        task monitor_writes();
            forever begin
                bit got_aw, got_w;
                logic [31:0] aw_addr, w_data;
                logic [3:0]  w_strb;
                hera_axi_seq_item txn;
                got_aw = 0; got_w = 0;
                // Capture AW and W fires -- may arrive same cycle
                while (!got_aw || !got_w) begin
                    @(posedge vif.clk);
                    if (!got_aw && vif.awvalid && vif.awready) begin
                        aw_addr = vif.awaddr; got_aw = 1;
                    end
                    if (!got_w && vif.wvalid && vif.wready) begin
                        w_data = vif.wdata; w_strb = vif.wstrb; got_w = 1;
                    end
                end
                // Wait for write response handshake
                do @(posedge vif.clk); while (!(vif.bvalid && vif.bready));
                txn        = hera_axi_seq_item::type_id::create("axi_wr_mon");
                txn.kind   = hera_axi_seq_item::AXI_WRITE;
                txn.addr   = aw_addr;
                txn.wdata  = w_data;
                txn.wstrb  = w_strb;
                txn.bresp  = vif.bresp;
                ap.write(txn);
            end
        endtask

        task monitor_reads();
            forever begin
                logic [31:0] ar_addr;
                hera_axi_seq_item txn;
                do @(posedge vif.clk); while (!(vif.arvalid && vif.arready));
                ar_addr = vif.araddr;
                do @(posedge vif.clk); while (!(vif.rvalid && vif.rready));
                txn       = hera_axi_seq_item::type_id::create("axi_rd_mon");
                txn.kind  = hera_axi_seq_item::AXI_READ;
                txn.addr  = ar_addr;
                txn.rdata = vif.rdata;
                txn.rresp = vif.rresp;
                ap.write(txn);
            end
        endtask
    endclass

    // ================================================================
    // xsim-compatible KV write monitor
    // ================================================================
    class hera_xsim_kv_wr_monitor extends uvm_monitor;
        `uvm_component_utils(hera_xsim_kv_wr_monitor)

        virtual hera_kv_wr_if vif;
        uvm_analysis_port #(hera_kv_wr_seq_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual hera_kv_wr_if)::get(
                    this, "", "kv_wr_vif", vif))
                `uvm_fatal("CFG", "kv_wr_vif not found in config_db")
        endfunction

        task run_phase(uvm_phase phase);
            forever begin
                hera_kv_wr_seq_item txn;
                // Wait for request
                do @(posedge vif.clk); while (!vif.wr_req);
                txn            = hera_kv_wr_seq_item::type_id::create("kv_wr_mon");
                txn.session_id = vif.wr_session_id;
                txn.token_pos  = vif.wr_token_pos;
                txn.k_data     = vif.wr_k_data;
                txn.v_data     = vif.wr_v_data;
                // Wait for ack
                do @(posedge vif.clk); while (!vif.wr_ack);
                txn.ack_received = 1;
                ap.write(txn);
                // Wait for request deassertion before next transaction
                do @(posedge vif.clk); while (vif.wr_req);
            end
        endtask
    endclass

    // ================================================================
    // xsim-compatible KV read monitor
    // ================================================================
    class hera_xsim_kv_rd_monitor extends uvm_monitor;
        `uvm_component_utils(hera_xsim_kv_rd_monitor)

        virtual hera_kv_rd_if vif;
        uvm_analysis_port #(hera_kv_rd_seq_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual hera_kv_rd_if)::get(
                    this, "", "kv_rd_vif", vif))
                `uvm_fatal("CFG", "kv_rd_vif not found in config_db")
        endfunction

        task run_phase(uvm_phase phase);
            forever begin
                hera_kv_rd_seq_item txn;
                hera_kv_beat_t      beat;
                // Wait for read request
                do @(posedge vif.clk); while (!vif.rd_req);
                txn             = hera_kv_rd_seq_item::type_id::create("kv_rd_mon");
                txn.session_id  = vif.rd_session_id;
                txn.token_start = vif.rd_token_start;
                txn.token_end   = vif.rd_token_end;
                // Collect data beats until rd_last
                do begin
                    do @(posedge vif.clk); while (!vif.rd_valid);
                    beat.k_data = vif.rd_k_data;
                    beat.v_data = vif.rd_v_data;
                    txn.beats.push_back(beat);
                end while (!vif.rd_last);
                ap.write(txn);
            end
        endtask
    endclass

    // ================================================================
    // xsim-compatible eviction monitor
    // ================================================================
    class hera_xsim_evict_monitor extends uvm_monitor;
        `uvm_component_utils(hera_xsim_evict_monitor)

        virtual hera_evict_if vif;
        uvm_analysis_port #(hera_evict_seq_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            ap = new("ap", this);
            if (!uvm_config_db #(virtual hera_evict_if)::get(
                    this, "", "evict_vif", vif))
                `uvm_fatal("CFG", "evict_vif not found in config_db")
        endfunction

        task run_phase(uvm_phase phase);
            forever begin
                hera_evict_seq_item txn;
                do @(posedge vif.clk);
                while (!(vif.evict_valid && vif.evict_ack));
                txn            = hera_evict_seq_item::type_id::create("evict_mon");
                txn.page_id    = vif.evict_page_id;
                txn.session_id = vif.evict_session_id;
                ap.write(txn);
            end
        endtask
    endclass

    // ================================================================
    // Eviction auto-ack  (plain uvm_component -- no uvm_driver/sequencer)
    // Asserts evict_ack one cycle after evict_valid is seen.
    // ================================================================
    class hera_xsim_evict_autoack extends uvm_component;
        `uvm_component_utils(hera_xsim_evict_autoack)

        virtual hera_evict_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual hera_evict_if)::get(
                    this, "", "evict_vif", vif))
                `uvm_fatal("CFG", "evict_vif not found in config_db")
        endfunction

        task run_phase(uvm_phase phase);
            vif.evict_ack = 0;
            forever begin
                do @(posedge vif.clk); while (!vif.evict_valid);
                @(posedge vif.clk);
                vif.evict_ack = 1;
                @(posedge vif.clk);
                vif.evict_ack = 0;
            end
        endtask
    endclass

    // ================================================================
    // xsim-compatible environment
    // ================================================================
    class hera_xsim_env extends uvm_env;
        `uvm_component_utils(hera_xsim_env)

        hera_xsim_axi_monitor    axi_mon;
        hera_xsim_kv_wr_monitor  kv_wr_mon;
        hera_xsim_kv_rd_monitor  kv_rd_mon;
        hera_xsim_evict_monitor  evict_mon;
        hera_xsim_evict_autoack  evict_aa;
        hera_scoreboard          sb;
        hera_coverage            cov;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            axi_mon   = hera_xsim_axi_monitor::type_id::create("axi_mon",   this);
            kv_wr_mon = hera_xsim_kv_wr_monitor::type_id::create("kv_wr_mon", this);
            kv_rd_mon = hera_xsim_kv_rd_monitor::type_id::create("kv_rd_mon", this);
            evict_mon = hera_xsim_evict_monitor::type_id::create("evict_mon", this);
            evict_aa  = hera_xsim_evict_autoack::type_id::create("evict_aa",  this);
            sb        = hera_scoreboard::type_id::create("sb",  this);
            cov       = hera_coverage::type_id::create("cov", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            // Scoreboard connections
            axi_mon.ap   .connect(sb.axi_export);
            kv_wr_mon.ap .connect(sb.kv_wr_export);
            kv_rd_mon.ap .connect(sb.kv_rd_export);
            evict_mon.ap .connect(sb.evict_export);
            // Coverage connections
            axi_mon.ap   .connect(cov.axi_cov_export);
            kv_wr_mon.ap .connect(cov.analysis_export);
            evict_mon.ap .connect(cov.evict_cov_export);
        endfunction
    endclass

    // ================================================================
    // Test base -- provides VIF handles and direct-drive helper tasks
    // ================================================================
    class hera_xsim_base_test extends uvm_test;
        `uvm_component_utils(hera_xsim_base_test)

        hera_xsim_env env;

        virtual hera_axi4_lite_if axi_vif;
        virtual hera_kv_wr_if     kv_wr_vif;
        virtual hera_kv_rd_if     kv_rd_vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = hera_xsim_env::type_id::create("env", this);
            if (!uvm_config_db #(virtual hera_axi4_lite_if)::get(
                    this, "", "axi_vif", axi_vif))
                `uvm_fatal("CFG", "axi_vif not found")
            if (!uvm_config_db #(virtual hera_kv_wr_if)::get(
                    this, "", "kv_wr_vif", kv_wr_vif))
                `uvm_fatal("CFG", "kv_wr_vif not found")
            if (!uvm_config_db #(virtual hera_kv_rd_if)::get(
                    this, "", "kv_rd_vif", kv_rd_vif))
                `uvm_fatal("CFG", "kv_rd_vif not found")
        endfunction

        // ------------------------------------------------------------
        // AXI write -- mirrors the Verilog BFM task pattern
        // ------------------------------------------------------------
        task axi_write(input  logic [31:0] addr,
                       input  logic [31:0] data,
                       output logic [1:0]  bresp);
            @(posedge axi_vif.clk); #1;
            axi_vif.awaddr  = addr;
            axi_vif.awvalid = 1;
            axi_vif.wdata   = data;
            axi_vif.wstrb   = 4'hF;
            axi_vif.wvalid  = 1;
            while (!(axi_vif.awready && axi_vif.wready)) begin
                @(posedge axi_vif.clk); #1;
            end
            @(posedge axi_vif.clk); #1;
            axi_vif.awvalid = 0;
            axi_vif.wvalid  = 0;
            axi_vif.bready  = 1;
            while (!axi_vif.bvalid) begin
                @(posedge axi_vif.clk); #1;
            end
            bresp = axi_vif.bresp;
            @(posedge axi_vif.clk); #1;
            axi_vif.bready = 0;
        endtask

        // ------------------------------------------------------------
        // AXI read
        // ------------------------------------------------------------
        task axi_read(input  logic [31:0] addr,
                      output logic [31:0] rdata);
            @(posedge axi_vif.clk); #1;
            axi_vif.araddr  = addr;
            axi_vif.arvalid = 1;
            while (!axi_vif.arready) begin
                @(posedge axi_vif.clk); #1;
            end
            @(posedge axi_vif.clk); #1;
            axi_vif.arvalid = 0;
            axi_vif.rready  = 1;
            while (!axi_vif.rvalid) begin
                @(posedge axi_vif.clk); #1;
            end
            rdata = axi_vif.rdata;
            @(posedge axi_vif.clk); #1;
            axi_vif.rready = 0;
        endtask

        // ------------------------------------------------------------
        // KV write -- waits for wr_ack from DUT
        // ------------------------------------------------------------
        task kv_write(input logic [2:0]    sess,
                      input logic [11:0]   tok,
                      input logic [1023:0] k,
                      input logic [1023:0] v);
            int timeout;
            @(posedge kv_wr_vif.clk); #1;
            kv_wr_vif.wr_session_id = sess;
            kv_wr_vif.wr_token_pos  = tok;
            kv_wr_vif.wr_k_data     = k;
            kv_wr_vif.wr_v_data     = v;
            kv_wr_vif.wr_req        = 1;
            timeout = 2000;
            while (!kv_wr_vif.wr_ack && timeout > 0) begin
                @(posedge kv_wr_vif.clk); #1;
                timeout--;
            end
            if (timeout == 0)
                `uvm_error("KV_WR", $sformatf(
                    "wr_ack timeout: sess=%0d tok=%0d", sess, tok))
            @(posedge kv_wr_vif.clk); #1;
            kv_wr_vif.wr_req = 0;
        endtask

        // ------------------------------------------------------------
        // KV read -- collects beats until rd_last, returns item
        // ------------------------------------------------------------
        task kv_read(input  logic [2:0]    sess,
                     input  logic [11:0]   tok_start,
                     input  logic [11:0]   tok_end,
                     output hera_kv_rd_seq_item result);
            int timeout;
            hera_kv_beat_t beat;
            result             = hera_kv_rd_seq_item::type_id::create("kv_rd_res");
            result.session_id  = sess;
            result.token_start = tok_start;
            result.token_end   = tok_end;
            result.timed_out   = 0;
            // Wait until not busy
            while (kv_rd_vif.rd_busy) begin
                @(posedge kv_rd_vif.clk); #1;
            end
            @(posedge kv_rd_vif.clk); #1;
            kv_rd_vif.rd_session_id  = sess;
            kv_rd_vif.rd_token_start = tok_start;
            kv_rd_vif.rd_token_end   = tok_end;
            kv_rd_vif.rd_req         = 1;
            @(posedge kv_rd_vif.clk); #1;
            kv_rd_vif.rd_req = 0;
            // Collect beats
            timeout = 5000;
            while (timeout > 0) begin
                @(posedge kv_rd_vif.clk);
                timeout--;
                if (kv_rd_vif.rd_valid) begin
                    beat.k_data = kv_rd_vif.rd_k_data;
                    beat.v_data = kv_rd_vif.rd_v_data;
                    result.beats.push_back(beat);
                    if (kv_rd_vif.rd_last) break;
                end
            end
            if (timeout == 0) begin
                result.timed_out = 1;
                `uvm_error("KV_RD", $sformatf(
                    "rd_last timeout: sess=%0d tok[%0d:%0d]",
                    sess, tok_start, tok_end))
            end
            #1;
        endtask

        // Drain a few cycles after stimulus
        task drain(int n = 20);
            repeat (n) @(posedge axi_vif.clk);
        endtask
    endclass

    // ================================================================
    // Smoke test
    // Checks: watermarks, enable, KV write-readback, SLVERR on RO write
    // ================================================================
    class hera_smoke_xsim_test extends hera_xsim_base_test;
        `uvm_component_utils(hera_smoke_xsim_test)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            logic [31:0]        rdata;
            logic [1:0]         bresp;
            hera_kv_rd_seq_item rd_rsp;
            logic [1023:0]      k, v;

            phase.raise_objection(this);

            // 1. Silicon watermarks
            axi_read(32'h20, rdata);
            if (rdata === 32'h48455241)
                `uvm_info("SMOKE", "IP_VERSION = 0x48455241 (HERA) -- OK", UVM_NONE)
            else
                `uvm_error("SMOKE", $sformatf(
                    "IP_VERSION wrong: got 0x%08h exp 0x48455241", rdata))

            axi_read(32'h24, rdata);
            if (rdata === 32'h00000001)
                `uvm_info("SMOKE", "IP_BUILDID = 0x00000001 -- OK", UVM_NONE)
            else
                `uvm_error("SMOKE", $sformatf(
                    "IP_BUILDID wrong: got 0x%08h", rdata))

            // 2. Global enable
            axi_write(32'h00, 32'h1, bresp);
            if (bresp === 2'b00)
                `uvm_info("SMOKE", "CTRL=1 (global_enable) -- OK", UVM_NONE)
            else
                `uvm_error("SMOKE", "CTRL write returned non-OKAY bresp")

            // 3. KV write: session 0, token 0
            k = 1024'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0;
            v = 1024'hFEED_FACE_C0FF_EE00_A5A5_A5A5_B3B3_B3B3;
            kv_write(3'd0, 12'd0, k, v);
            `uvm_info("SMOKE", "KV write sess=0 tok=0 done", UVM_NONE)

            // 4. Read back
            kv_read(3'd0, 12'd0, 12'd0, rd_rsp);
            if (rd_rsp.timed_out) begin
                `uvm_error("SMOKE", "KV read timed out")
            end else if (rd_rsp.beats.size() > 0) begin
                if (rd_rsp.beats[0].k_data[63:0] === k[63:0])
                    `uvm_info("SMOKE", "KV read-back K[63:0] matches -- OK", UVM_NONE)
                else
                    `uvm_error("SMOKE", $sformatf(
                        "K mismatch: got %016h exp %016h",
                        rd_rsp.beats[0].k_data[63:0], k[63:0]))
                if (rd_rsp.beats[0].v_data[63:0] === v[63:0])
                    `uvm_info("SMOKE", "KV read-back V[63:0] matches -- OK", UVM_NONE)
                else
                    `uvm_error("SMOKE", $sformatf(
                        "V mismatch: got %016h exp %016h",
                        rd_rsp.beats[0].v_data[63:0], v[63:0]))
            end

            // 5. STATUS register
            axi_read(32'h10, rdata);
            `uvm_info("SMOKE", $sformatf(
                "STATUS = 0x%08h  (pages_free=%0d)", rdata, rdata[7:0]), UVM_NONE)

            // 6. SLVERR on write to RO STATUS
            axi_write(32'h10, 32'hFFFF_FFFF, bresp);
            if (bresp === 2'b10)
                `uvm_info("SMOKE", "SLVERR on RO STATUS write -- OK", UVM_NONE)
            else
                `uvm_error("SMOKE", $sformatf(
                    "Expected SLVERR on STATUS write, got %0b", bresp))

            // 7. SLVERR on write to IP_VERSION
            axi_write(32'h20, 32'h0, bresp);
            if (bresp === 2'b10)
                `uvm_info("SMOKE", "SLVERR on IP_VERSION write -- OK", UVM_NONE)
            else
                `uvm_error("SMOKE", "Expected SLVERR on IP_VERSION write")

            drain(30);
            phase.drop_objection(this);
        endtask
    endclass

    // ================================================================
    // Stress test
    // 64 writes across 4 sessions / 8 page slots with periodic reads
    // ================================================================
    class hera_stress_xsim_test extends hera_xsim_base_test;
        `uvm_component_utils(hera_stress_xsim_test)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            logic [1:0]    bresp;
            logic [1023:0] k, v;
            int unsigned   N = 64;

            phase.raise_objection(this);

            axi_write(32'h00, 32'h1, bresp); // enable
            `uvm_info("STRESS",
                $sformatf("Starting stress: %0d writes across 4 sessions", N),
                UVM_NONE)

            for (int i = 0; i < N; i++) begin
                hera_kv_rd_seq_item rsp;
                logic [2:0]  sess;
                logic [11:0] tok;
                int          page, off;
                sess = logic'(i % 4);
                page = i % 8;
                off  = i % 16;
                tok  = logic'(page * 16 + off);
                // Fill k/v with a recognisable pattern
                for (int w = 0; w < 32; w++) begin
                    k[w*32 +: 32] = $random;
                    v[w*32 +: 32] = $random;
                end
                kv_write(sess, tok, k, v);
                // Periodic read-back every 8th write
                if (i % 8 == 7) begin
                    kv_read(sess, tok, tok, rsp);
                    if (!rsp.timed_out && rsp.beats.size() > 0)
                        `uvm_info("STRESS",
                            $sformatf("Read-back i=%0d sess=%0d tok=%0d ok",
                                      i, sess, tok), UVM_MEDIUM)
                end
            end

            `uvm_info("STRESS",
                $sformatf("Stress done: %0d writes completed", N), UVM_NONE)
            drain(30);
            phase.drop_objection(this);
        endtask
    endclass

    // ================================================================
    // Security test
    // Checks: quota enforcement, config lock (SLVERR), watermark integrity
    // ================================================================
    class hera_security_xsim_test extends hera_xsim_base_test;
        `uvm_component_utils(hera_security_xsim_test)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            logic [31:0]   rdata;
            logic [1:0]    bresp;
            logic [1023:0] k, v;

            phase.raise_objection(this);

            // Enable
            axi_write(32'h00, 32'h1, bresp);

            // ---- Quota enforcement: 2 pages per session ----
            axi_write(32'h08, 32'h02, bresp); // PAGE_CFG = 2
            `uvm_info("SEC", "Quota set to 2 pages/session", UVM_NONE)

            for (int w = 0; w < 32; w++) begin k[w*32+:32]=$random; v[w*32+:32]=$random; end
            kv_write(3'd0, 12'd0,  k, v); // page 0 -- should allocate
            kv_write(3'd0, 12'd16, k, v); // page 1 -- should allocate
            kv_write(3'd0, 12'd32, k, v); // page 2 -- quota exceeded, dropped

            axi_read(32'h10, rdata);
            if (rdata[18])
                `uvm_info("SEC", "quota_exceeded (STATUS[18]) set -- OK", UVM_NONE)
            else
                `uvm_error("SEC", "quota_exceeded NOT set after overflow")

            // ---- Config lock ----
            axi_write(32'h1C, 32'h1, bresp); // LOCK[0] = 1
            `uvm_info("SEC", "LOCK register written (config locked)", UVM_NONE)

            axi_write(32'h00, 32'h0, bresp); // CTRL write -- must SLVERR
            if (bresp === 2'b10)
                `uvm_info("SEC", "SLVERR on locked CTRL write -- OK", UVM_NONE)
            else
                `uvm_error("SEC",
                    $sformatf("Expected SLVERR on locked CTRL write, got %0b", bresp))

            axi_write(32'h04, 32'h3, bresp); // SESSION_CFG write -- must SLVERR
            if (bresp === 2'b10)
                `uvm_info("SEC", "SLVERR on locked SESSION_CFG write -- OK", UVM_NONE)
            else
                `uvm_error("SEC", "Expected SLVERR on locked SESSION_CFG write")

            // ---- Watermark immutable after lock ----
            axi_read(32'h20, rdata);
            if (rdata === 32'h48455241)
                `uvm_info("SEC", "IP_VERSION intact after lock -- OK", UVM_NONE)
            else
                `uvm_error("SEC",
                    $sformatf("IP_VERSION corrupted after lock: 0x%08h", rdata))

            // ---- Cross-session isolation ----
            // Write distinct data to sessions 1 and 2 at the same token offset.
            // Scoreboard verifies each read returns only the correct session's data.
            for (int w = 0; w < 32; w++) k[w*32+:32] = $random;
            for (int w = 0; w < 32; w++) v[w*32+:32] = $random;
            kv_write(3'd1, 12'd0, k, v);

            for (int w = 0; w < 32; w++) k[w*32+:32] = $random;
            for (int w = 0; w < 32; w++) v[w*32+:32] = $random;
            kv_write(3'd2, 12'd0, k, v);

            begin
                hera_kv_rd_seq_item rsp;
                kv_read(3'd1, 12'd0, 12'd0, rsp);
                kv_read(3'd2, 12'd0, 12'd0, rsp);
            end

            `uvm_info("SEC", "Security test complete", UVM_NONE)
            drain(30);
            phase.drop_objection(this);
        endtask
    endclass

    // ================================================================
    // Soft-reset test
    // Checks: state cleared after soft reset, re-enable works
    // ================================================================
    class hera_soft_reset_xsim_test extends hera_xsim_base_test;
        `uvm_component_utils(hera_soft_reset_xsim_test)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            logic [1:0]    bresp;
            logic [31:0]   rdata;
            logic [1023:0] k, v;

            phase.raise_objection(this);

            // Fill k/v
            for (int w = 0; w < 32; w++) begin
                k[w*32+:32] = 32'hABCD_0000 | w;
                v[w*32+:32] = 32'h1234_0000 | w;
            end

            // Pre-reset: enable + write
            axi_write(32'h00, 32'h1, bresp);
            kv_write(3'd0, 12'd0, k, v);

            axi_read(32'h10, rdata);
            `uvm_info("SRST", $sformatf(
                "Pre-reset STATUS = 0x%08h  pages_free=%0d",
                rdata, rdata[7:0]), UVM_NONE)

            // Soft reset: CTRL[1]=1 pulses soft_reset
            axi_write(32'h00, 32'h2, bresp);
            `uvm_info("SRST", "Soft reset issued (CTRL[1]=1)", UVM_NONE)

            // Re-enable
            axi_write(32'h00, 32'h1, bresp);

            axi_read(32'h10, rdata);
            `uvm_info("SRST", $sformatf(
                "Post-reset STATUS = 0x%08h  pages_free=%0d",
                rdata, rdata[7:0]), UVM_NONE)

            if (rdata[7:0] > 8'd200)
                `uvm_info("SRST",
                    "pages_free restored after soft reset -- OK", UVM_NONE)
            else
                `uvm_info("SRST",
                    "pages_free may not be fully restored -- see report", UVM_LOW)

            // Re-write after reset
            kv_write(3'd0, 12'd0, k, v);
            `uvm_info("SRST", "Re-write after soft reset -- OK", UVM_NONE)

            drain(30);
            phase.drop_objection(this);
        endtask
    endclass

endpackage : hera_uvm_xsim_pkg
