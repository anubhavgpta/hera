// A single read beat captured by the monitor / returned by the driver
typedef struct {
    logic [1023:0] k_data;
    logic [1023:0] v_data;
} hera_kv_beat_t;

class hera_kv_rd_seq_item extends uvm_sequence_item;
    `uvm_object_utils(hera_kv_rd_seq_item)

    rand logic [2:0]  session_id;
    rand logic [11:0] token_start;
    rand logic [11:0] token_end;

    // Populated by driver/monitor with each rd_valid beat
    hera_kv_beat_t beats[$];
    bit            timed_out;

    constraint c_session { session_id < 8; }
    constraint c_range {
        token_start < 12'd512;
        token_end   >= token_start;
        token_end   < 12'd512;
        (token_end - token_start) < 12'd32; // keep bursts sane
    }

    function new(string name = "hera_kv_rd_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("KV_RD sess=%0d tok[%0d:%0d] beats=%0d timeout=%0b",
                         session_id, token_start, token_end,
                         beats.size(), timed_out);
    endfunction
endclass
