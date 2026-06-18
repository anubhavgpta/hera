class hera_kv_wr_monitor extends uvm_monitor;
    `uvm_component_utils(hera_kv_wr_monitor)

    virtual hera_kv_wr_if vif;
    uvm_analysis_port #(hera_kv_wr_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db #(virtual hera_kv_wr_if)::get(this, "", "kv_wr_vif", vif))
            `uvm_fatal("CFG", "kv_wr_vif not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        hera_kv_wr_seq_item txn;
        forever begin
            // Wait for request assertion
            @(vif.monitor_cb iff vif.monitor_cb.wr_req);
            txn            = hera_kv_wr_seq_item::type_id::create("kv_wr_obs");
            txn.session_id = vif.monitor_cb.wr_session_id;
            txn.token_pos  = vif.monitor_cb.wr_token_pos;
            txn.k_data     = vif.monitor_cb.wr_k_data;
            txn.v_data     = vif.monitor_cb.wr_v_data;
            // Wait for ack
            @(vif.monitor_cb iff vif.monitor_cb.wr_ack);
            txn.ack_received = 1;
            ap.write(txn);
        end
    endtask
endclass
