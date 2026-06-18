class hera_evict_monitor extends uvm_monitor;
    `uvm_component_utils(hera_evict_monitor)

    virtual hera_evict_if vif;
    uvm_analysis_port #(hera_evict_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db #(virtual hera_evict_if)::get(this, "", "evict_vif", vif))
            `uvm_fatal("CFG", "evict_vif not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        hera_evict_seq_item txn;
        forever begin
            // Report when the eviction is accepted (valid & ack both high)
            @(vif.monitor_cb iff (vif.monitor_cb.evict_valid && vif.monitor_cb.evict_ack));
            txn            = hera_evict_seq_item::type_id::create("evict_obs");
            txn.page_id    = vif.monitor_cb.evict_page_id;
            txn.session_id = vif.monitor_cb.evict_session_id;
            ap.write(txn);
        end
    endtask
endclass
