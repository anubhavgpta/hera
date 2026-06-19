class hera_kv_wr_seq_item extends uvm_sequence_item;
    `uvm_object_utils(hera_kv_wr_seq_item)

    rand logic [2:0]     session_id;
    rand logic [11:0]    token_pos;
    rand logic [1023:0]  k_data;
    rand logic [1023:0]  v_data;

    // Set by driver once wr_ack is observed
    bit ack_received;

    // 32 logical pages * 16 tokens = 512 token positions per session
    constraint c_session { session_id < 8; }
    constraint c_token   { token_pos  < 12'd512; }

    function new(string name = "hera_kv_wr_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("KV_WR sess=%0d tok=%0d k[63:0]=%016h v[63:0]=%016h ack=%0b",
                         session_id, token_pos, k_data[63:0], v_data[63:0], ack_received);
    endfunction
endclass
