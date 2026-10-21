module riscv_core_ifbus_lint_top
    import riscv_pkg::*;
(
    input logic clk,
    input logic rst
);

    // Instantiate the instruction mem interface
    mem_bus_if imem (
        .clk (clk),
        .rst (rst)
    );

    retire_t rvfi;
    logic    fetch_error;

    // Instantiate new processor
    riscv_core_ifbus u_core (
        .clk         (clk),
        .rst         (rst),
        .imem        (imem),
        .rvfi        (rvfi),
        .fetch_error (fetch_error)
    );

    // Placeholder memory responses for lint only
    assign imem.req_ready = 1'b1;
    assign imem.rsp_valid = 1'b0;
    assign imem.rsp_rdata = '0;
    assign imem.rsp_err   = 1'b0;

endmodule
