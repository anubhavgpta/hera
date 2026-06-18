class hera_evict_seq_item extends uvm_sequence_item;
    `uvm_object_utils(hera_evict_seq_item)

    logic [7:0] page_id;
    logic [2:0] session_id;

    function new(string name = "hera_evict_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("EVICT page=%0d sess=%0d", page_id, session_id);
    endfunction
endclass
