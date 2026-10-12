`include "rvfi_macros.vh"

module rvfi_wrapper
    import riscv_pkg::*;
(
    input   logic   clock,
    input   logic   reset,

    `RVFI_OUTPUTS
);

    // --------------------------------------------------------
    // Internal retirement interface
    // --------------------------------------------------------

    retire_t rvfi;


    // --------------------------------------------------------
    // Processor
    // --------------------------------------------------------

    riscv_core u_core
    (
        .clk            (clock),
        .rst            (reset),

        .rvfi            (rvfi)
    );


    // --------------------------------------------------------
    // RVFI adapter
    // --------------------------------------------------------

    rvfi_adapter u_rvfi_adapter
    (
        .rvfi           (rvfi),
        .*
    );


endmodule

