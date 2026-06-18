// Virtual sequencer holds references to all agent sequencers.
// Tests create virtual sequences and start them on this sequencer.
class hera_virtual_sequencer extends uvm_sequencer;
    `uvm_component_utils(hera_virtual_sequencer)

    uvm_sequencer #(hera_axi_seq_item)    axi_seqr;
    uvm_sequencer #(hera_kv_wr_seq_item)  kv_wr_seqr;
    uvm_sequencer #(hera_kv_rd_seq_item)  kv_rd_seqr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
endclass
