module mem_wb_reg
    import riscv_pkg::*;
(
    input   logic       clk,
    input   logic       rst,

    input   mem_wb_t    mem_wb_d,
    output  mem_wb_t    mem_wb_q
);

    always_ff @( posedge clk ) begin
        if (rst)
            mem_wb_q <= '0;
        else
            mem_wb_q <= mem_wb_d;
    end

endmodule

