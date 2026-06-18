class hera_axi_seq_item extends uvm_sequence_item;
    `uvm_object_utils(hera_axi_seq_item)

    typedef enum logic { AXI_WRITE = 1'b0, AXI_READ = 1'b1 } axi_kind_e;

    rand axi_kind_e  kind;
    rand logic [31:0] addr;
    rand logic [31:0] wdata;
    rand logic [3:0]  wstrb;

    // Populated by driver after transaction completes
    logic [1:0]  bresp;
    logic [31:0] rdata;
    logic [1:0]  rresp;

    // Constrain to valid register addresses in the Hera register map
    constraint c_reg_addr {
        addr[31:8] == 24'h0;
        addr[7:0] inside {8'h00, 8'h04, 8'h08, 8'h10, 8'h14, 8'h18, 8'h1C, 8'h20, 8'h24};
    }
    constraint c_full_strobe { wstrb == 4'hF; }

    function new(string name = "hera_axi_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        if (kind == AXI_WRITE)
            return $sformatf("AXI_WR addr=%08h data=%08h strb=%0h bresp=%0b",
                             addr, wdata, wstrb, bresp);
        else
            return $sformatf("AXI_RD addr=%08h rdata=%08h rresp=%0b",
                             addr, rdata, rresp);
    endfunction
endclass
