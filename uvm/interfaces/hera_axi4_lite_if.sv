// AXI4-Lite interface for Hera host control port
interface hera_axi4_lite_if (input logic clk, input logic rst_n);
    logic        awvalid;
    logic        awready;
    logic [31:0] awaddr;
    logic        wvalid;
    logic        wready;
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        bvalid;
    logic        bready;
    logic [1:0]  bresp;
    logic        arvalid;
    logic        arready;
    logic [31:0] araddr;
    logic        rvalid;
    logic        rready;
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        irq;

    clocking driver_cb @(posedge clk);
        default input #1 output #1;
        output awvalid, awaddr, wvalid, wdata, wstrb, bready, arvalid, araddr, rready;
        input  awready, wready, bvalid, bresp, arready, rvalid, rdata, rresp, irq;
    endclocking

    clocking monitor_cb @(posedge clk);
        default input #1;
        input awvalid, awready, awaddr;
        input wvalid,  wready,  wdata, wstrb;
        input bvalid,  bready,  bresp;
        input arvalid, arready, araddr;
        input rvalid,  rready,  rdata, rresp;
        input irq;
    endclocking

    modport driver_mp  (clocking driver_cb,  input clk, rst_n);
    modport monitor_mp (clocking monitor_cb, input clk, rst_n);
endinterface
