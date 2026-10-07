module riscv_core
    import riscv_pkg::*;
#(
    parameter   logic [XLEN-1:0]        RESET_PC = '0,
    parameter   int unsigned            IMEM_DEPTH = 256,
    parameter   string                  IMEM_INIT_FILE = ""
)(
    input   logic   clk,
    input   logic   rst
);

    // --------------------------------------------------------
    // Pipeline control
    // --------------------------------------------------------

    logic       pc_en;
    logic       if_id_en;
    logic       if_id_flush;
    logic       id_ex_flush;
    logic       stall;

    assign stall        = 1'b0; // PLACEHOLDER ****************

    assign if_id_flush  = redirect_valid;
    assign id_ex_flush  = redirect_valid | stall;

    assign pc_en        = redirect_valid | ~stall;
    assign if_id_en     = ~stall;


    // --------------------------------------------------------
    // Pipeline Register Bundles
    // --------------------------------------------------------

    if_id_t     if_id_d;
    if_id_t     if_id_q;

    id_ex_t     id_ex_d;
    id_ex_t     id_ex_q;

    ex_mem_t    ex_mem_d;
    ex_mem_t    ex_mem_q;

    mem_wb_t    mem_wb_d;
    mem_wb_t    mem_wb_q;


    // --------------------------------------------------------
    // EX -> IF control-flow redirect
    // --------------------------------------------------------

    logic       redirect_valid;
    addr_t      redirect_pc;


    // --------------------------------------------------------
    // WB -> ID register file writeback
    // --------------------------------------------------------

    logic       wb_reg_write;
    reg_addr_t  wb_rd_addr;
    word_t      wb_rd_wdata;


    // --------------------------------------------------------
    // Instantiate IF
    // --------------------------------------------------------

    if_stage #(
        .RESET_PC           (RESET_PC),
        .IMEM_DEPTH         (IMEM_DEPTH),
        .IMEM_INIT_FILE     (IMEM_INIT_FILE)
    ) u_if_stage (
        .clk                (clk),
        .rst                (rst),

        .pc_en              (pc_en),
        
        .redirect_valid     (redirect_valid),
        .redirect_pc        (redirect_pc),

        .if_id_d            (if_id_d)
    );


    // --------------------------------------------------------
    // Instantiate IF/ID register
    // --------------------------------------------------------

    if_id_reg u_if_id_reg
    (
        .clk                (clk),
        .rst                (rst),
        .en                 (if_id_en),
        .flush              (if_id_flush),
        .d                  (if_id_d),
        .q                  (if_id_q)
    );


    // --------------------------------------------------------
    // Instantiate ID
    // --------------------------------------------------------

    id_stage u_id_stage
    (
        .clk                (clk),

        .if_id_q            (if_id_q),

        .wb_reg_write        (wb_reg_write),
        .wb_rd_addr          (wb_rd_addr),
        .wb_rd_wdata         (wb_rd_wdata),

        .id_ex_d            (id_ex_d)
    );


    // --------------------------------------------------------
    // Instantiate ID/EX register
    // --------------------------------------------------------

    id_ex_reg u_id_ex_reg
    (
        .clk                (clk),
        .rst                (rst),
        .flush              (id_ex_flush),

        .id_ex_d            (id_ex_d),
        .id_ex_q            (id_ex_q)
    );


    // --------------------------------------------------------
    // Instantiate EX
    // --------------------------------------------------------

    ex_stage u_ex_stage
    (
        .id_ex_q            (id_ex_q),

        .ex_mem_d           (ex_mem_d),

        .redirect_valid     (redirect_valid),
        .redirect_pc        (redirect_pc)
    );


    // --------------------------------------------------------
    // Instantiate EX/MEM register
    // --------------------------------------------------------

    ex_mem_reg u_ex_mem_reg
    (
        .clk                (clk),
        .rst                (rst),

        .ex_mem_d            (ex_mem_d),
        .ex_mem_q            (ex_mem_q)
    );


    // --------------------------------------------------------
    // Instantiate MEM
    // --------------------------------------------------------

    mem_stage u_mem_stage
    (
        .clk                (clk),        

        .ex_mem_q           (ex_mem_q),

        .mem_wb_d           (mem_wb_d)
    );


    // --------------------------------------------------------
    // Instantiate MEM/WB register
    // --------------------------------------------------------

    mem_wb_reg u_mem_wb_reg
    (
        .clk                (clk),
        .rst                (rst),

        .mem_wb_d           (mem_wb_d),
        .mem_wb_q           (mem_wb_q)
    );


    // --------------------------------------------------------
    // Instantiate WB
    // --------------------------------------------------------

    wb_stage u_wb_stage
    (
        .mem_wb_q           (mem_wb_q),

        .wb_reg_write       (wb_reg_write),
        .wb_rd_addr         (wb_rd_addr),
        .wb_rd_wdata        (wb_rd_wdata)
    );


endmodule

