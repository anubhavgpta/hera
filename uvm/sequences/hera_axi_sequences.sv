// Low-level AXI helper sequences used by virtual sequences

// Single register write; caller reads back .rsp for BRESP value
class hera_axi_write_seq extends uvm_sequence #(hera_axi_seq_item);
    `uvm_object_utils(hera_axi_write_seq)

    logic [31:0] addr;
    logic [31:0] data;
    logic [3:0]  strb = 4'hF;
    logic [1:0]  rsp;      // populated after body() returns

    function new(string name = "hera_axi_write_seq");
        super.new(name);
    endfunction

    task body();
        hera_axi_seq_item req = hera_axi_seq_item::type_id::create("req");
        start_item(req);
        req.kind  = hera_axi_seq_item::AXI_WRITE;
        req.addr  = addr;
        req.wdata = data;
        req.wstrb = strb;
        finish_item(req);
        rsp = req.bresp;
    endtask
endclass

// Single register read; caller reads back .rdata
class hera_axi_read_seq extends uvm_sequence #(hera_axi_seq_item);
    `uvm_object_utils(hera_axi_read_seq)

    logic [31:0] addr;
    logic [31:0] rdata;    // populated after body() returns

    function new(string name = "hera_axi_read_seq");
        super.new(name);
    endfunction

    task body();
        hera_axi_seq_item req = hera_axi_seq_item::type_id::create("req");
        start_item(req);
        req.kind = hera_axi_seq_item::AXI_READ;
        req.addr = addr;
        finish_item(req);
        rdata = req.rdata;
    endtask
endclass

// Enable Hera: CTRL[0] = 1
class hera_enable_seq extends uvm_sequence #(hera_axi_seq_item);
    `uvm_object_utils(hera_enable_seq)
    function new(string name = "hera_enable_seq"); super.new(name); endfunction
    task body();
        hera_axi_write_seq wr = hera_axi_write_seq::type_id::create("wr");
        wr.addr = 32'h00;
        wr.data = 32'h1;
        wr.start(m_sequencer);
    endtask
endclass

// Soft-reset: CTRL[1] = 1 (self-clearing in RTL)
class hera_soft_reset_seq extends uvm_sequence #(hera_axi_seq_item);
    `uvm_object_utils(hera_soft_reset_seq)
    function new(string name = "hera_soft_reset_seq"); super.new(name); endfunction
    task body();
        hera_axi_write_seq wr = hera_axi_write_seq::type_id::create("wr");
        wr.addr = 32'h00;
        wr.data = 32'h3; // bit1=soft_reset, bit0=global_enable
        wr.start(m_sequencer);
        // Re-enable after reset
        wr = hera_axi_write_seq::type_id::create("re_enable");
        wr.addr = 32'h00;
        wr.data = 32'h1;
        wr.start(m_sequencer);
    endtask
endclass

// Set max pages per session quota (0 = unlimited)
class hera_set_quota_seq extends uvm_sequence #(hera_axi_seq_item);
    `uvm_object_utils(hera_set_quota_seq)
    logic [7:0] quota;
    function new(string name = "hera_set_quota_seq"); super.new(name); endfunction
    task body();
        hera_axi_write_seq wr = hera_axi_write_seq::type_id::create("wr");
        wr.addr = 32'h08;
        wr.data = {24'h0, quota};
        wr.start(m_sequencer);
    endtask
endclass

// Lock configuration registers (sticky — only cleared by hard rst_n)
class hera_lock_seq extends uvm_sequence #(hera_axi_seq_item);
    `uvm_object_utils(hera_lock_seq)
    function new(string name = "hera_lock_seq"); super.new(name); endfunction
    task body();
        hera_axi_write_seq wr = hera_axi_write_seq::type_id::create("wr");
        wr.addr = 32'h1C;
        wr.data = 32'h1;
        wr.start(m_sequencer);
    endtask
endclass
