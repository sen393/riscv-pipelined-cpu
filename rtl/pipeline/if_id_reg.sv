module if_id_reg
    import riscv_pkg::*;
(
    input   logic               clk,
    input   logic               rst,
    input   logic               en,
    input   logic               flush,

    input   if_id_t             d,
    output  if_id_t             q
);

    // Priority: rst, flush, en, hold (last)
    always_ff @( posedge clk ) begin
        if (rst)
            q <= '0;
        else if (flush)
            q <= '0;
        else if (en)
            q <= d;
    end

endmodule

