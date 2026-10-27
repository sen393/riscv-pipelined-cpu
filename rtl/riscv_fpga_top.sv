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

    clk_wiz_0 u_clk_wiz (
        .clk_in1  (clk),
        .reset    (rst),
        .clk_out1 (cpu_clk),
        .locked   (clk_locked)
    );
    
    // --------------------------------------------------------
    // CPU clock and reset
    // --------------------------------------------------------
    
    logic cpu_clk;
    logic clk_locked;
    
    logic reset_request;
    logic [1:0] reset_sync_q;
    logic cpu_rst;
    
    // Hold reset while the MMCM is not locked
    assign reset_request = rst || !clk_locked;
    
    // Asynchronous assertion, synchronous deassertion
    always_ff @(posedge cpu_clk or posedge reset_request) begin
        if (reset_request)
            reset_sync_q <= 2'b11;
        else
            reset_sync_q <= {reset_sync_q[0], 1'b0};
    end
    
    assign cpu_rst = reset_sync_q[1];


    // --------------------------------------------------------
    // System init
    // --------------------------------------------------------

    retire_t rvfi;

    riscv_system #(
        .IMEM_INIT_FILE ("bram_smoke.mem")
    ) u_system (
        .clk                (cpu_clk),
        .rst                (cpu_rst),
        .rvfi               (rvfi),
        .fetch_error        (fetch_error),
        .data_access_fault  (data_access_fault)
    );

    // Observe processor retirement
    assign retire_valid = rvfi.valid;
    assign debug_data   = rvfi.rd_wdata[7:0];

endmodule
