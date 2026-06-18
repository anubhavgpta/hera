class hera_axi_driver extends uvm_driver #(hera_axi_seq_item);
    `uvm_component_utils(hera_axi_driver)

    virtual hera_axi4_lite_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual hera_axi4_lite_if)::get(this, "", "axi_vif", vif))
            `uvm_fatal("CFG", "axi_vif not found in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        hera_axi_seq_item req;
        // Idle
        vif.driver_cb.awvalid <= 0;  vif.driver_cb.wvalid  <= 0;
        vif.driver_cb.bready  <= 0;  vif.driver_cb.arvalid <= 0;
        vif.driver_cb.rready  <= 0;
        @(posedge vif.clk iff vif.rst_n);
        forever begin
            seq_item_port.get_next_item(req);
            if (req.kind == hera_axi_seq_item::AXI_WRITE)
                do_write(req);
            else
                do_read(req);
            seq_item_port.item_done();
        end
    endtask

    task do_write(hera_axi_seq_item req);
        // Drive AW and W in parallel
        fork
            begin
                vif.driver_cb.awvalid <= 1;
                vif.driver_cb.awaddr  <= req.addr;
                @(vif.driver_cb iff vif.driver_cb.awready);
                vif.driver_cb.awvalid <= 0;
            end
            begin
                vif.driver_cb.wvalid <= 1;
                vif.driver_cb.wdata  <= req.wdata;
                vif.driver_cb.wstrb  <= req.wstrb;
                @(vif.driver_cb iff vif.driver_cb.wready);
                vif.driver_cb.wvalid <= 0;
            end
        join
        // Collect write response
        vif.driver_cb.bready <= 1;
        @(vif.driver_cb iff vif.driver_cb.bvalid);
        req.bresp = vif.driver_cb.bresp;
        @(vif.driver_cb);
        vif.driver_cb.bready <= 0;
    endtask

    task do_read(hera_axi_seq_item req);
        vif.driver_cb.arvalid <= 1;
        vif.driver_cb.araddr  <= req.addr;
        @(vif.driver_cb iff vif.driver_cb.arready);
        vif.driver_cb.arvalid <= 0;
        // Collect read data
        vif.driver_cb.rready <= 1;
        @(vif.driver_cb iff vif.driver_cb.rvalid);
        req.rdata = vif.driver_cb.rdata;
        req.rresp = vif.driver_cb.rresp;
        @(vif.driver_cb);
        vif.driver_cb.rready <= 0;
    endtask
endclass
