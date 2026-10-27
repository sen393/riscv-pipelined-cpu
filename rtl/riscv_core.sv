module riscv_core
    import riscv_pkg::*;
#(
    parameter   logic [XLEN-1:0]        RESET_PC = '0
)(
    input   logic       clk,
    input   logic       rst,

    // Memory bus interfaces
    mem_bus_if.master   imem,
    mem_bus_if.master   dmem,

    // Architectural retirement
    output  retire_t    rvfi,

    // Terminal memory access errors
    output  logic       fetch_error,
    output  logic       data_access_fault
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

    logic       id_ex_en;
    logic       id_ex_flush;

    logic       ex_mem_en;

    logic       load_use_stall; // stall from hazard unit
    logic       mem_stall;  // stall from waiting for memory

    logic       redirect_fire;
    logic       ex_exception_fire;


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
        !load_use_stall                         &&
        !mem_stall                              &&
        !redirect_fire                          &&
        !ex_exception_fire                      &&
        !exception_pending_q;

    assign ex_exception =
        ex_instr_addr_misaligned || ex_data_addr_misaligned;

    always_ff @(posedge clk) begin
        if (rst)
            // Stuck on HIGH until rst, temporary solution
            exception_pending_q <= 1'b0;
        else if (exception_accept || ex_exception_fire)
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

        .stall              (load_use_stall)
    );


    // --------------------------------------------------------
    // Pipeline control
    // --------------------------------------------------------

    assign redirect_fire =
            redirect_valid      &&
            !mem_stall          &&
            !ex_exception       &&
            !exception_pending_q;

    assign ex_exception_fire =
            ex_exception    &&
            !mem_stall      &&
            !exception_pending_q;

    // Deliver instruction only when not stalled by either cond
    assign decode_ready = !load_use_stall && !mem_stall;

    // Stop fetch after terminal exceptions/errors
    assign stop_fetch   =
            exception_accept        ||
            ex_exception_fire       ||
            exception_pending_q     ||
            data_access_fault;


    // --------------------------------------------------------
    // IF/ID control
    // --------------------------------------------------------

    // Do not apply younger redirects/flushes while MEM waiting
    assign if_id_flush =
        !mem_stall &&
       (redirect_fire               ||
        exception_accept            ||
        ex_exception_fire           ||
        exception_pending_q);

    // Hold IF/ID during either type of stall
    // Allow normal flush behavior during load use stall
    assign if_id_en = !mem_stall &&
                     (!load_use_stall || if_id_flush);


    // --------------------------------------------------------
    // ID/EX control
    // --------------------------------------------------------

    // Hold ID/EX during mem stall
    assign id_ex_en     = !mem_stall;

    // Add bubbles for load use stalls, redirects, exceptions
    assign id_ex_flush  =
        !mem_stall &&
       (redirect_fire       ||
        load_use_stall      ||
        ex_exception_fire   ||
        exception_pending_q);


    // --------------------------------------------------------
    // EX/MEM control
    // --------------------------------------------------------

    // Preserve instr in mem until completed
    assign ex_mem_en = !mem_stall;


    // --------------------------------------------------------
    // Instantiate IF
    // --------------------------------------------------------

    if_stage #(
        .RESET_PC           (RESET_PC)
    ) u_if_stage (
        .clk                (clk),
        .rst                (rst),

        .decode_ready       (decode_ready),
        .stop_fetch         (stop_fetch),
        
        .redirect_valid     (redirect_fire),
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

        .en                 (id_ex_en),
        .flush              (id_ex_flush),

        .wb_reg_write       (wb_reg_write),
        .wb_rd_addr         (wb_rd_addr),
        .wb_rd_wdata        (wb_rd_wdata),

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

        .en                 (ex_mem_en),

        .ex_mem_d           (ex_mem_d),
        .ex_mem_q           (ex_mem_q)
    );


    // --------------------------------------------------------
    // Instantiate MEM
    // --------------------------------------------------------

    mem_stage u_mem_stage
    (
        .clk                (clk),        
        .rst                (rst),

        .dmem               (dmem),

        .ex_mem_q           (ex_mem_q),

        .mem_wb_d           (mem_wb_d),

        .mem_stall          (mem_stall),
        .access_fault       (data_access_fault)
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

