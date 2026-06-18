// KV write interface — DATA_WIDTH(16)*HEAD_DIM(64) = 1024-bit data
interface hera_kv_wr_if #(parameter KV_W = 1024) (input logic clk);
    logic           wr_req;
    logic [2:0]     wr_session_id;
    logic [11:0]    wr_token_pos;
    logic [KV_W-1:0] wr_k_data;
    logic [KV_W-1:0] wr_v_data;
    logic           wr_ack;

    clocking driver_cb @(posedge clk);
        default input #1 output #1;
        output wr_req, wr_session_id, wr_token_pos, wr_k_data, wr_v_data;
        input  wr_ack;
    endclocking

    clocking monitor_cb @(posedge clk);
        default input #1;
        input wr_req, wr_session_id, wr_token_pos, wr_k_data, wr_v_data, wr_ack;
    endclocking

    modport driver_mp  (clocking driver_cb,  input clk);
    modport monitor_mp (clocking monitor_cb, input clk);
endinterface
