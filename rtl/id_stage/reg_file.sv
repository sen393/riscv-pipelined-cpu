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


    // Register read with WB-to-ID bypass
    always_comb begin

        // Default: x0 always returns zero
        rs1_data = '0;
        rs2_data = '0;

        // Read rs1
        if (rs1_addr != '0) begin
            if (rd_we && (rd_addr == rs1_addr))
                rs1_data = rd_wdata;
            else
                rs1_data = x[rs1_addr];
        end

        // Read rs2
        if (rs2_addr != '0) begin
            if (rd_we && (rd_addr == rs2_addr))
                rs2_data = rd_wdata;
            else
                rs2_data = x[rs2_addr];
        end

    end

endmodule

