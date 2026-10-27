module riscv_fpga_top
    import riscv_pkg::*;
(
    input  logic       clk,
    input  logic       rst,

    output logic [7:0] debug_data,
    output logic       retire_valid,
    output logic       fetch_error,
    output logic       data_access_fault
);

    retire_t rvfi;

    riscv_system #(
        .IMEM_INIT_FILE ("bram_smoke.mem")
    ) u_system (
        .clk                (clk),
        .rst                (rst),
        .rvfi               (rvfi),
        .fetch_error        (fetch_error),
        .data_access_fault  (data_access_fault)
    );

    // Observe processor retirement
    assign retire_valid = rvfi.valid;
    assign debug_data   = rvfi.rd_wdata[7:0];

endmodule
