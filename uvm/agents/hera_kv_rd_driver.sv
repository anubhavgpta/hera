class hera_kv_rd_driver extends uvm_driver #(hera_kv_rd_seq_item);
    `uvm_component_utils(hera_kv_rd_driver)

    virtual hera_kv_rd_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual hera_kv_rd_if)::get(this, "", "kv_rd_vif", vif))
            `uvm_fatal("CFG", "kv_rd_vif not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        hera_kv_rd_seq_item req;
        vif.driver_cb.rd_req         <= 0;
        vif.driver_cb.rd_session_id  <= 0;
        vif.driver_cb.rd_token_start <= 0;
        vif.driver_cb.rd_token_end   <= 0;
        forever begin
            seq_item_port.get_next_item(req);
            drive_read(req);
            seq_item_port.item_done();
        end
    endtask

    task drive_read(hera_kv_rd_seq_item req);
        hera_kv_beat_t beat;
        int timeout_cnt;

        // Don't start a new read while engine is busy
        if (vif.driver_cb.rd_busy)
            @(vif.driver_cb iff !vif.driver_cb.rd_busy);

        vif.driver_cb.rd_req         <= 1;
        vif.driver_cb.rd_session_id  <= req.session_id;
        vif.driver_cb.rd_token_start <= req.token_start;
        vif.driver_cb.rd_token_end   <= req.token_end;
        @(vif.driver_cb);
        vif.driver_cb.rd_req <= 0;

        req.beats.delete();
        req.timed_out = 0;
        timeout_cnt   = 0;

        // Collect burst beats until rd_last
        forever begin
            @(vif.driver_cb);
            timeout_cnt++;
            if (timeout_cnt > 5000) begin
                `uvm_error("KV_RD_DRV", $sformatf(
                    "rd_last timeout: sess=%0d tok[%0d:%0d]",
                    req.session_id, req.token_start, req.token_end))
                req.timed_out = 1;
                break;
            end
            if (vif.driver_cb.rd_valid) begin
                beat.k_data = vif.driver_cb.rd_k_data;
                beat.v_data = vif.driver_cb.rd_v_data;
                req.beats.push_back(beat);
                if (vif.driver_cb.rd_last) break;
            end
        end
    endtask
endclass
