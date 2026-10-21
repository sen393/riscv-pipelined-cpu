module riscv_core_ifbus
    import riscv_pkg::*;
#(
    parameter   logic [XLEN-1:0]        RESET_PC = '0,
    parameter   int unsigned            DMEM_DEPTH = 256
)(
    input   logic       clk,
    input   logic       rst,

    // Instruction memory bus
    mem_bus_if.master   imem,

    // Architectural retirement
    output  retire_t    rvfi,

    // Terminal instr fetch error
    output  logic       fetch_error
);

    // --------------------------------------------------------
    // Exception control signals
    // --------------------------------------------------------

    logic       exception_pending_q;
    logic       exception_accept;

    logic       ex_instr_addr_misaligned;
    logic       ex_data_addr_misaligned;
    logic       ex_exception;


    // --------------------------------------------------------
    // Pipeline control
    // --------------------------------------------------------

    logic       decode_ready;
    logic       stop_fetch;

    logic       if_id_en;
    logic       if_id_flush;
    logic       id_ex_flush;
    logic       stall;      // From hazard unit


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
    // Hazard/Forwarding signals
    // --------------------------------------------------------

    fwd_sel_e   fwd_a_sel;
    fwd_sel_e   fwd_b_sel;

    word_t      ex_mem_fwd_data;
    word_t      mem_wb_fwd_data;


    // --------------------------------------------------------
    // Hazard/Forwarding logic
    // --------------------------------------------------------

    assign mem_wb_fwd_data = wb_rd_wdata;
    always_comb begin
        case (ex_mem_q.ctrl.wb_sel)
            WB_ALU  : ex_mem_fwd_data = ex_mem_q.alu_result;
        //  WB_MEM  : not forwardable from EX/MEM
            WB_PC4  : ex_mem_fwd_data = ex_mem_q.pc_plus4;
            default : ex_mem_fwd_data = '0;
        endcase
    end


    // --------------------------------------------------------
    // Exception control logic
    // --------------------------------------------------------

    assign exception_accept =
        if_id_q.valid                           &&
        (id_ex_d.ctrl.exc_kind != EXC_NONE)     &&
        !stall                                  &&
        !redirect_valid                         &&
        !ex_exception                           &&
        !exception_pending_q;

    assign ex_exception =
        ex_instr_addr_misaligned || ex_data_addr_misaligned;

    always_ff @(posedge clk) begin
        if (rst)
            // Stuck on HIGH until rst, temporary solution
            exception_pending_q <= 1'b0;
        else if (exception_accept || ex_exception)
            exception_pending_q <= 1'b1;
    end


    // --------------------------------------------------------
    // Instantiate Hazard unit
    // --------------------------------------------------------

    hazard_unit u_hazard_unit
    (
        .id_ex_d            (id_ex_d),
        .id_ex_q            (id_ex_q),
        .ex_mem_q           (ex_mem_q),
        .mem_wb_q           (mem_wb_q),

        .fwd_a_sel          (fwd_a_sel),
        .fwd_b_sel          (fwd_b_sel),

        .stall              (stall)
    );


    // --------------------------------------------------------
    // Pipeline control
    // --------------------------------------------------------

    assign decode_ready = ~stall;

    assign stop_fetch   =
            exception_accept        |
            ex_exception            |
            exception_pending_q;

    // Flush younger instructions from IF/ID
    assign if_id_flush =
        redirect_valid              |
        exception_accept            |
        ex_exception                |
        exception_pending_q;

    // Allow IF/ID to be cleared even during a stall
    assign if_id_en = ~stall | if_id_flush;

    // Insert bubbles into ID/EX after ECALL advances
    assign id_ex_flush =
        redirect_valid              |
        stall                       |
        ex_exception                |
        exception_pending_q;


    // --------------------------------------------------------
    // Instantiate IF
    // --------------------------------------------------------

    if_stage_bus #(
        .RESET_PC           (RESET_PC)
    ) u_if_stage (
        .clk                (clk),
        .rst                (rst),

        .decode_ready       (decode_ready),
        .stop_fetch         (stop_fetch),
        
        .redirect_valid     (redirect_valid),
        .redirect_pc        (redirect_pc),

        .imem               (imem),

        .if_id_d            (if_id_d),

        .fetch_error        (fetch_error)
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
        .id_ex_q                (id_ex_q),

        .fwd_a_sel              (fwd_a_sel),
        .fwd_b_sel              (fwd_b_sel),

        .ex_mem_fwd_data        (ex_mem_fwd_data),
        .mem_wb_fwd_data        (mem_wb_fwd_data),

        .ex_mem_d               (ex_mem_d),

        .redirect_valid         (redirect_valid),
        .redirect_pc            (redirect_pc),

        .instr_addr_misaligned  (ex_instr_addr_misaligned),
        .data_addr_misaligned   (ex_data_addr_misaligned)
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

    mem_stage #(
        .DMEM_DEPTH         (DMEM_DEPTH)
    ) u_mem_stage (
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
        .clk                (clk),
        .rst                (rst),

        .mem_wb_q           (mem_wb_q),

        .wb_reg_write       (wb_reg_write),
        .wb_rd_addr         (wb_rd_addr),
        .wb_rd_wdata        (wb_rd_wdata),

        .rvfi               (rvfi)
    );


endmodule

