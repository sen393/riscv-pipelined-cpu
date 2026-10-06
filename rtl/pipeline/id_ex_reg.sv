module if_ex_reg
    import riscv_pkg::*;
(
    input   logic               clk,
    input   logic               rst,
    input   logic               flush,

    input   id_ex_t             id_ex_d,
    output  id_ex_t             id_ex_q
);

    always_ff @( posedge clk ) begin
        if (rst)
            id_ex_q <= '0; 
        else if (flush)
            id_ex_q <= '0;
        else
            id_ex_q <= id_ex_d;
    end

endmodule