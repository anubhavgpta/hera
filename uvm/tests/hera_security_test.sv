class hera_security_test extends hera_base_test;
    `uvm_component_utils(hera_security_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    task run_phase(uvm_phase phase);
        hera_security_vseq vseq;
        phase.raise_objection(this);
        #200;
        vseq = hera_security_vseq::type_id::create("vseq");
        vseq.start(vseqr);
        #200;
        phase.drop_objection(this);
    endtask
endclass
