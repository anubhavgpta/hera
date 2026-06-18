class hera_stress_test extends hera_base_test;
    `uvm_component_utils(hera_stress_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        hera_stress_vseq vseq;
        phase.raise_objection(this);
        #200;
        vseq = hera_stress_vseq::type_id::create("vseq");
        vseq.num_writes = 512; // fill the 256-page cache twice over
        vseq.start(vseqr);
        #200;
        phase.drop_objection(this);
    endtask
endclass
