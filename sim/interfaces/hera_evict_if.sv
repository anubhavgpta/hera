`timescale 1ns/1ps
// Eviction offload interface
interface hera_evict_if (input logic clk);
    logic       evict_valid;
    logic [7:0] evict_page_id;
    logic [2:0] evict_session_id;
    logic       evict_ack;

    clocking driver_cb @(posedge clk);
        default input #1 output #1;
        output evict_ack;
        input  evict_valid, evict_page_id, evict_session_id;
    endclocking

    clocking monitor_cb @(posedge clk);
        default input #1;
        input evict_valid, evict_page_id, evict_session_id, evict_ack;
    endclocking

    modport driver_mp  (clocking driver_cb,  input clk);
    modport monitor_mp (clocking monitor_cb, input clk);
endinterface
