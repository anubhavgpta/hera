class hera_evict_agent extends uvm_agent;
    `uvm_component_utils(hera_evict_agent)

    hera_evict_driver  driver;
    hera_evict_monitor monitor;
    uvm_analysis_port #(hera_evict_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        monitor = hera_evict_monitor::type_id::create("monitor", this);
        ap      = new("ap", this);
        if (get_is_active() == UVM_ACTIVE)
            driver = hera_evict_driver::type_id::create("driver", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        monitor.ap.connect(ap);
    endfunction
endclass
