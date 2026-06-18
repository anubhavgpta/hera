class hera_kv_wr_driver extends uvm_driver #(hera_kv_wr_seq_item);
    `uvm_component_utils(hera_kv_wr_driver)

    virtual hera_kv_wr_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual hera_kv_wr_if)::get(this, "", "kv_wr_vif", vif))
            `uvm_fatal("CFG", "kv_wr_vif not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        hera_kv_wr_seq_item req;
        vif.driver_cb.wr_req        <= 0;
        vif.driver_cb.wr_session_id <= 0;
        vif.driver_cb.wr_token_pos  <= 0;
        vif.driver_cb.wr_k_data     <= 0;
        vif.driver_cb.wr_v_data     <= 0;
        forever begin
            seq_item_port.get_next_item(req);
            drive_write(req);
            seq_item_port.item_done();
        end
    endtask

    task drive_write(hera_kv_wr_seq_item req);
        int timeout_cnt;
        @(vif.driver_cb);
        vif.driver_cb.wr_req        <= 1;
        vif.driver_cb.wr_session_id <= req.session_id;
        vif.driver_cb.wr_token_pos  <= req.token_pos;
        vif.driver_cb.wr_k_data     <= req.k_data;
        vif.driver_cb.wr_v_data     <= req.v_data;
        // Hold req until ack (write FSM takes 3-5 cycles minimum)
        timeout_cnt = 0;
        req.ack_received = 0;
        do begin
            @(vif.driver_cb);
            timeout_cnt++;
            if (timeout_cnt > 2000) begin
                `uvm_error("KV_WR_DRV", $sformatf(
                    "wr_ack timeout after 2000 cycles: sess=%0d tok=%0d",
                    req.session_id, req.token_pos))
                break;
            end
        end while (!vif.driver_cb.wr_ack);
        req.ack_received = vif.driver_cb.wr_ack;
        @(vif.driver_cb);
        vif.driver_cb.wr_req <= 0;
    endtask
endclass
