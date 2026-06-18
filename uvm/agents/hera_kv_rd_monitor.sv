class hera_kv_rd_monitor extends uvm_monitor;
    `uvm_component_utils(hera_kv_rd_monitor)

    virtual hera_kv_rd_if vif;
    uvm_analysis_port #(hera_kv_rd_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db #(virtual hera_kv_rd_if)::get(this, "", "kv_rd_vif", vif))
            `uvm_fatal("CFG", "kv_rd_vif not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        hera_kv_rd_seq_item txn;
        hera_kv_beat_t      beat;
        forever begin
            // Capture request
            @(vif.monitor_cb iff vif.monitor_cb.rd_req);
            txn             = hera_kv_rd_seq_item::type_id::create("kv_rd_obs");
            txn.session_id  = vif.monitor_cb.rd_session_id;
            txn.token_start = vif.monitor_cb.rd_token_start;
            txn.token_end   = vif.monitor_cb.rd_token_end;
            txn.beats.delete();
            // Collect burst
            forever begin
                @(vif.monitor_cb);
                if (vif.monitor_cb.rd_valid) begin
                    beat.k_data = vif.monitor_cb.rd_k_data;
                    beat.v_data = vif.monitor_cb.rd_v_data;
                    txn.beats.push_back(beat);
                    if (vif.monitor_cb.rd_last) break;
                end
            end
            ap.write(txn);
        end
    endtask
endclass
