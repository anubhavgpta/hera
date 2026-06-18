// Low-level KV helper sequences

// Single directed KV write
class hera_kv_wr_seq extends uvm_sequence #(hera_kv_wr_seq_item);
    `uvm_object_utils(hera_kv_wr_seq)

    logic [2:0]     session_id;
    logic [11:0]    token_pos;
    logic [1023:0]  k_data;
    logic [1023:0]  v_data;

    function new(string name = "hera_kv_wr_seq"); super.new(name); endfunction

    task body();
        hera_kv_wr_seq_item req = hera_kv_wr_seq_item::type_id::create("req");
        start_item(req);
        req.session_id = session_id;
        req.token_pos  = token_pos;
        req.k_data     = k_data;
        req.v_data     = v_data;
        finish_item(req);
    endtask
endclass

// Single directed KV read; caller accesses .rsp_item.beats after completion
class hera_kv_rd_seq extends uvm_sequence #(hera_kv_rd_seq_item);
    `uvm_object_utils(hera_kv_rd_seq)

    logic [2:0]  session_id;
    logic [11:0] token_start;
    logic [11:0] token_end;

    hera_kv_rd_seq_item rsp_item; // populated by body()

    function new(string name = "hera_kv_rd_seq"); super.new(name); endfunction

    task body();
        hera_kv_rd_seq_item req = hera_kv_rd_seq_item::type_id::create("req");
        start_item(req);
        req.session_id  = session_id;
        req.token_start = token_start;
        req.token_end   = token_end;
        finish_item(req);
        rsp_item = req;
    endtask
endclass

// Randomised burst of KV writes across all sessions
class hera_kv_rand_wr_seq extends uvm_sequence #(hera_kv_wr_seq_item);
    `uvm_object_utils(hera_kv_rand_wr_seq)

    int unsigned count = 32;

    function new(string name = "hera_kv_rand_wr_seq"); super.new(name); endfunction

    task body();
        hera_kv_wr_seq_item req;
        repeat (count) begin
            req = hera_kv_wr_seq_item::type_id::create("req");
            start_item(req);
            if (!req.randomize())
                `uvm_fatal("RAND", "hera_kv_wr_seq_item randomize() failed")
            finish_item(req);
        end
    endtask
endclass
