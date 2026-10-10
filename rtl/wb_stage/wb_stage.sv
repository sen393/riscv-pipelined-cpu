module wb_stage
    import riscv_pkg::*;
(
    input   logic       clk,
    input   logic       rst,

    // From MEM/WB pipeline reg
    input   mem_wb_t    mem_wb_q,

    // To register file
    output  logic       wb_reg_write,
    output  reg_addr_t  wb_rd_addr,
    output  word_t      wb_rd_wdata,

    output  retire_t    rvfi
);
    // --------------------------------------------------------
    // Retirement signals
    // --------------------------------------------------------
    
    logic [63:0]    retire_order_q;
    logic           retire_fire;

    assign retire_fire = mem_wb_q.valid && !rst;


    // --------------------------------------------------------
    // Register writeback
    // --------------------------------------------------------

    always_comb begin

        // Register destination
        wb_rd_addr      = mem_wb_q.rd;

        // Only allow valid instr to write reg
        wb_reg_write    =   mem_wb_q.valid          &&
                            mem_wb_q.ctrl.reg_write &&
                            (mem_wb_q.rd != '0);  

        // Writeback mux
        unique case (mem_wb_q.ctrl.wb_sel)

            WB_ALU  : wb_rd_wdata = mem_wb_q.alu_result;
            WB_MEM  : wb_rd_wdata = mem_wb_q.mem_data;
            WB_PC4  : wb_rd_wdata = mem_wb_q.pc_plus4;
            default : wb_rd_wdata = '0;

        endcase

    end


    // --------------------------------------------------------
    // Retirement order counter
    // --------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst)
            retire_order_q <= '0;
        else if (retire_fire)
            retire_order_q <= retire_order_q + 64'd1;
    end



    // --------------------------------------------------------
    // Retirement interface
    // --------------------------------------------------------

    always_comb begin
        rvfi = '0;

        if (retire_fire) begin
            // Retirement info
            rvfi.valid = 1'b1;
            rvfi.order = retire_order_q;
            rvfi.insn  = mem_wb_q.instr;

            // Source register info
            rvfi.rs1_addr  = mem_wb_q.meta.rs1_addr;
            rvfi.rs2_addr  = mem_wb_q.meta.rs2_addr;
            rvfi.rs1_rdata = mem_wb_q.meta.rs1_rdata;
            rvfi.rs2_rdata = mem_wb_q.meta.rs2_rdata;

            // Destination register info
            rvfi.rd_addr  = wb_reg_write ? wb_rd_addr  : '0;
            rvfi.rd_wdata = wb_reg_write ? wb_rd_wdata : '0;

            // Program counter info
            rvfi.pc_rdata = mem_wb_q.pc;
            rvfi.pc_wdata = mem_wb_q.meta.next_pc;

            // Memory access info
            rvfi.mem_addr  = mem_wb_q.meta.mem_addr;
            rvfi.mem_rmask = mem_wb_q.meta.mem_rmask;
            rvfi.mem_wmask = mem_wb_q.meta.mem_wmask;
            rvfi.mem_rdata = mem_wb_q.meta.mem_rdata;
            rvfi.mem_wdata = mem_wb_q.meta.mem_wdata;

            // trap, halt, and intr remain zero
        end
    end


endmodule

