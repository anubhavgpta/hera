class hera_axi_monitor extends uvm_monitor;
    `uvm_component_utils(hera_axi_monitor)

    virtual hera_axi4_lite_if vif;
    uvm_analysis_port #(hera_axi_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db #(virtual hera_axi4_lite_if)::get(this, "", "axi_vif", vif))
            `uvm_fatal("CFG", "axi_vif not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        @(posedge vif.clk iff vif.rst_n);
        fork
            monitor_writes();
            monitor_reads();
        join
    endtask

    task monitor_writes();
        hera_axi_seq_item txn;
        logic [31:0] aw_addr, w_data;
        logic [3:0]  w_strb;
        logic        got_aw, got_w;
        forever begin
            got_aw = 0; got_w = 0;
            // Collect AW and W independently (either order)
            fork
                begin
                    @(vif.monitor_cb iff (vif.monitor_cb.awvalid && vif.monitor_cb.awready));
                    aw_addr = vif.monitor_cb.awaddr;
                    got_aw  = 1;
                end
                begin
                    @(vif.monitor_cb iff (vif.monitor_cb.wvalid && vif.monitor_cb.wready));
                    w_data = vif.monitor_cb.wdata;
                    w_strb = vif.monitor_cb.wstrb;
                    got_w  = 1;
                end
            join
            // Wait for write response
            @(vif.monitor_cb iff (vif.monitor_cb.bvalid && vif.monitor_cb.bready));
            txn        = hera_axi_seq_item::type_id::create("axi_wr_obs");
            txn.kind   = hera_axi_seq_item::AXI_WRITE;
            txn.addr   = aw_addr;
            txn.wdata  = w_data;
            txn.wstrb  = w_strb;
            txn.bresp  = vif.monitor_cb.bresp;
            ap.write(txn);
        end
    endtask

    task monitor_reads();
        hera_axi_seq_item txn;
        logic [31:0] ar_addr;
        forever begin
            @(vif.monitor_cb iff (vif.monitor_cb.arvalid && vif.monitor_cb.arready));
            ar_addr = vif.monitor_cb.araddr;
            @(vif.monitor_cb iff (vif.monitor_cb.rvalid && vif.monitor_cb.rready));
            txn       = hera_axi_seq_item::type_id::create("axi_rd_obs");
            txn.kind  = hera_axi_seq_item::AXI_READ;
            txn.addr  = ar_addr;
            txn.rdata = vif.monitor_cb.rdata;
            txn.rresp = vif.monitor_cb.rresp;
            ap.write(txn);
        end
    endtask
endclass
