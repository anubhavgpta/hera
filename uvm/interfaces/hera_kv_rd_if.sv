`timescale 1ns/1ps
// KV read interface — burst response via rd_valid/rd_last
interface hera_kv_rd_if #(parameter KV_W = 1024) (input logic clk);
    logic            rd_req;
    logic [2:0]      rd_session_id;
    logic [11:0]     rd_token_start;
    logic [11:0]     rd_token_end;
    logic [KV_W-1:0] rd_k_data;
    logic [KV_W-1:0] rd_v_data;
    logic            rd_valid;
    logic            rd_last;
    logic            rd_busy;

    clocking driver_cb @(posedge clk);
        default input #1 output #1;
        output rd_req, rd_session_id, rd_token_start, rd_token_end;
        input  rd_k_data, rd_v_data, rd_valid, rd_last, rd_busy;
    endclocking

    clocking monitor_cb @(posedge clk);
        default input #1;
        input rd_req, rd_session_id, rd_token_start, rd_token_end;
        input rd_k_data, rd_v_data, rd_valid, rd_last, rd_busy;
    endclocking

    modport driver_mp  (clocking driver_cb,  input clk);
    modport monitor_mp (clocking monitor_cb, input clk);
endinterface
