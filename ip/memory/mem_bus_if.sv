
interface mem_bus_if #(
    parameter int unsigned  ADDR_W = 32,
    parameter int unsigned  DATA_W = 32,
    parameter int unsigned  STRB_W = DATA_W / 8
)(
    input logic clk,
    input logic rst
);

    // Request channel
    logic               req_valid;
    logic               req_ready;
    logic [ADDR_W-1:0]  req_addr;
    logic               req_write;
    logic [DATA_W-1:0]  req_wdata;
    logic [STRB_W-1:0]  req_wstrb;

    // Response channel
    logic               rsp_valid;
    logic               rsp_ready;
    logic [DATA_W-1:0]  rsp_rdata;
    logic               rsp_err;

    // CPU side
    modport master (
        input  clk, rst,
               req_ready,
               rsp_valid, rsp_rdata, rsp_err,

        output req_valid, req_addr, req_write,
               req_wdata, req_wstrb, rsp_ready
    );

    // Memory/peripheral side
    modport slave (
        input  clk, rst,
               req_valid, req_addr, req_write,
               req_wdata, req_wstrb, rsp_ready,

        output req_ready,
               rsp_valid, rsp_rdata, rsp_err
    );

endinterface
