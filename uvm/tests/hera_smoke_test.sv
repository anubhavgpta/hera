class hera_smoke_test extends hera_base_test;
    `uvm_component_utils(hera_smoke_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        hera_smoke_vseq vseq;
        phase.raise_objection(this);
        #200; // reset
        vseq = hera_smoke_vseq::type_id::create("vseq");
        vseq.start(vseqr);
        #100;
        phase.drop_objection(this);
    endtask
endclass
