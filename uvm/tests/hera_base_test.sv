class hera_base_test extends uvm_test;
    `uvm_component_utils(hera_base_test)

    hera_env              env;
    hera_virtual_sequencer vseqr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env   = hera_env::type_id::create("env",   this);
        vseqr = hera_virtual_sequencer::type_id::create("vseqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        vseqr.axi_seqr   = env.axi_agent.sequencer;
        vseqr.kv_wr_seqr = env.kv_wr_agent.sequencer;
        vseqr.kv_rd_seqr = env.kv_rd_agent.sequencer;
    endfunction

    // Subclasses override run_phase to run their virtual sequence
    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        #200; // hold through reset (10 cycles @ 10ns period)
        phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
        uvm_report_server rs = uvm_report_server::get_server();
        if (rs.get_severity_count(UVM_ERROR) == 0 &&
            rs.get_severity_count(UVM_FATAL) == 0)
            `uvm_info("TEST", "*** TEST PASSED ***", UVM_NONE)
        else
            `uvm_info("TEST", "*** TEST FAILED ***", UVM_NONE)
    endfunction
endclass
