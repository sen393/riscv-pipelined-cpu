module reg_file
    import riscv_pkg::*;
(
    input   logic                   clk,
    input   reg_addr_t              rs1_addr,
    input   reg_addr_t              rs2_addr,
    input   reg_addr_t              rd_addr,
    input   word_t                  rd_wdata,
    input   logic                   rd_we,

    output  word_t                  rs1_data,
    output  word_t                  rs2_data
);

    word_t x [0:NUM_REGS-1];

    // Synchronous write port
    always_ff @( posedge clk ) begin
        if (rd_we && rd_addr != '0) 
            x[rd_addr] <= rd_wdata;
    end

    // Asynchronous read ports
    assign rs1_data = ( rs1_addr == '0 ) ? '0 : x[rs1_addr];
    assign rs2_data = ( rs2_addr == '0 ) ? '0 : x[rs2_addr];

endmodule

