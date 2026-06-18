class hera_kv_rd_agent extends uvm_agent;
    `uvm_component_utils(hera_kv_rd_agent)

    hera_kv_rd_driver  driver;
    hera_kv_rd_monitor monitor;
    uvm_sequencer #(hera_kv_rd_seq_item) sequencer;
    uvm_analysis_port #(hera_kv_rd_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = hera_kv_rd_monitor::type_id::create("monitor", this);
        ap      = new("ap", this);
        if (get_is_active() == UVM_ACTIVE) begin
            driver    = hera_kv_rd_driver::type_id::create("driver", this);
            sequencer = uvm_sequencer #(hera_kv_rd_seq_item)::type_id::create("sequencer", this);
        end
    endfunction

    function void connect_phase(uvm_phase phase);
        monitor.ap.connect(ap);
        if (get_is_active() == UVM_ACTIVE)
            driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction
endclass
