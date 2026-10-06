module pc_reg
    import riscv_pkg::*;
#(
    parameter logic [XLEN-1:0] RESET_PC = '0
)
(
    input   logic               clk,
    input   logic               rst,
    input   logic               en,     // Active high en

    input   logic [XLEN-1:0]    next_pc,
    output  logic [XLEN-1:0]    pc
);

    always_ff @( posedge clk ) begin
        if (rst)
            pc <= RESET_PC;
        else begin
            if (en)
                pc <= next_pc;
        end
    end

endmodule

