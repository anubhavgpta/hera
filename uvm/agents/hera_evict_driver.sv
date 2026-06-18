// Auto-ack driver: asserts evict_ack one cycle after evict_valid is seen.
// The eviction_engine holds evict_valid until ack, so single-cycle ack is safe.
class hera_evict_driver extends uvm_driver #(hera_evict_seq_item);
    `uvm_component_utils(hera_evict_driver)

    virtual hera_evict_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual hera_evict_if)::get(this, "", "evict_vif", vif))
            `uvm_fatal("CFG", "evict_vif not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        vif.driver_cb.evict_ack <= 0;
        forever begin
            @(vif.driver_cb iff vif.driver_cb.evict_valid);
            @(vif.driver_cb);
            vif.driver_cb.evict_ack <= 1;
            @(vif.driver_cb);
            vif.driver_cb.evict_ack <= 0;
        end
    endtask
endclass
