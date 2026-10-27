module riscv_system
    import riscv_pkg::*;
#(
    parameter logic [XLEN-1:0] RESET_PC       = '0,

    // Instruction memory configuration
    parameter int unsigned     IMEM_DEPTH_WORDS = 1024,
    parameter logic [XLEN-1:0] IMEM_BASE_ADDR   = '0,
    parameter string           IMEM_INIT_FILE   = "",

    // Data memory configuration
    parameter int unsigned     DMEM_DEPTH_WORDS = 1024,
    parameter logic [XLEN-1:0] DMEM_BASE_ADDR   = '0,
    parameter string           DMEM_INIT_FILE   = ""
)(
    input  logic    clk,
    input  logic    rst,

    // Architectural retirement
    output retire_t rvfi,

    // Error indicators
    output logic    fetch_error,
    output logic    data_access_fault
);

    // --------------------------------------------------------
    // Memory bus interfaces
    // --------------------------------------------------------

    mem_bus_if imem_bus (
        .clk (clk),
        .rst (rst)
    );

    mem_bus_if dmem_bus (
        .clk (clk),
        .rst (rst)
    );


    // --------------------------------------------------------
    // RISC-V Core
    // --------------------------------------------------------

    riscv_core #(
        .RESET_PC (RESET_PC)
    ) u_core (
        .clk                (clk),
        .rst                (rst),

        .imem               (imem_bus),
        .dmem               (dmem_bus),

        .rvfi               (rvfi),
        .fetch_error        (fetch_error),
        .data_access_fault  (data_access_fault)
    );


    // --------------------------------------------------------
    // Instruction BRAM
    // --------------------------------------------------------

    bram_adapter #(
        .DEPTH_WORDS (IMEM_DEPTH_WORDS),
        .BASE_ADDR   (IMEM_BASE_ADDR),
        .INIT_FILE   (IMEM_INIT_FILE),
        .READ_ONLY   (1'b1)
    ) u_imem (
        .clk (clk),
        .rst (rst),
        .bus (imem_bus)
    );


    // --------------------------------------------------------
    // Data BRAM
    // --------------------------------------------------------

    bram_adapter #(
        .DEPTH_WORDS (DMEM_DEPTH_WORDS),
        .BASE_ADDR   (DMEM_BASE_ADDR),
        .INIT_FILE   (DMEM_INIT_FILE),
        .READ_ONLY   (1'b0)
    ) u_dmem (
        .clk (clk),
        .rst (rst),
        .bus (dmem_bus)
    );

endmodule
