module ex_mem_reg
    import riscv_pkg::*;
(
    input   logic       clk,
    input   logic       rst,

    input   ex_mem_t    ex_mem_d,
    output  ex_mem_t    ex_mem_q
);

    always_ff @( posedge clk ) begin
        if (rst) 
            ex_mem_q <= '0;
        else
            ex_mem_q <= ex_mem_d;
    end

endmodule