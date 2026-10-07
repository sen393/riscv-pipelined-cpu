module wb_stage
    import riscv_pkg::*;
(
    // From MEM/WB pipeline reg
    input   mem_wb_t    mem_wb_q,

    // To register file
    output  logic       wb_reg_write,
    output  reg_addr_t  wb_rd_addr,
    output  word_t      wb_rd_wdata
);

    always_comb begin

        // Register destination
        wb_rd_addr      = mem_wb_q.rd;

        // Only allow valid instr to write reg
        wb_reg_write    = mem_wb_q.valid && mem_wb_q.ctrl.mem_write;  

        // Writeback mux
        unique case (mem_wb_q.ctrl.wb_sel)

            WB_ALU  : wb_rd_wdata = mem_wb_q.alu_result;
            WB_MEM  : wb_rd_wdata = mem_wb_q.mem_data;
            WB_PC4  : wb_rd_wdata = mem_wb_q.pc_plus4;
            default : wb_rd_wdata = '0;

        endcase

    end

endmodule