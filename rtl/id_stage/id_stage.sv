module id_stage
    import riscv_pkg::*;
(
    input   logic               clk,

    // From IF/ID pipeline reg
    input   if_id_t             if_id_q,

    // From WB stage
    input   logic               wb_reg_write,
    input   reg_addr_t          wb_rd_addr,
    input   word_t              wb_rd_wdata,

    // To ID/EX pipeline reg
    output  id_ex_t             id_ex_d
);

    // --------------------------------------------------------
    // Register fields
    // --------------------------------------------------------

    reg_addr_t  rs1_addr;
    reg_addr_t  rs2_addr;
    reg_addr_t  rd_addr;

    assign rs1_addr = if_id_q.instr[19:15];
    assign rs2_addr = if_id_q.instr[24:20];
    assign rd_addr  = if_id_q.instr[11:7];


    // --------------------------------------------------------
    // Decode outputs
    // --------------------------------------------------------
    ctrl_t      ctrl;
    word_t      imm_ext;


    // --------------------------------------------------------
    // Register file outputs
    // --------------------------------------------------------
    word_t      rs1_data;
    word_t      rs2_data;


    // --------------------------------------------------------
    // Decoder
    // --------------------------------------------------------

    decoder u_decoder
    (
        .instr      (if_id_q.instr),
        .ctrl       (ctrl)
    );


    // --------------------------------------------------------
    // Immediate Generator
    // --------------------------------------------------------
    
    imm_gen u_imm_gen
    (
        .imm_sel    (ctrl.imm_sel),
        .instr      (if_id_q.instr),
        .imm_ext    (imm_ext)
    );


    // --------------------------------------------------------
    // Register File
    // --------------------------------------------------------

    reg_file u_reg_file
    (
        .clk        (clk),

        .rs1_addr   (rs1_addr),
        .rs2_addr   (rs2_addr),

        .rd_addr    (wb_rd_addr),
        .rd_wdata   (wb_rd_wdata),
        .rd_we      (wb_reg_write),

        .rs1_data   (rs1_data),
        .rs2_data   (rs2_data)
    );


    always_comb begin
        id_ex_d             = '0;

        id_ex_d.valid       = if_id_q.valid;

        id_ex_d.pc          = if_id_q.pc;
        id_ex_d.pc_plus4    = if_id_q.pc_plus4;
        id_ex_d.instr       = if_id_q.instr;

        id_ex_d.rs1         = rs1_addr;
        id_ex_d.rs2         = rs2_addr;
        id_ex_d.rd          = rd_addr;

        id_ex_d.rs1_data    = rs1_data;
        id_ex_d.rs2_data    = rs2_data;
        id_ex_d.imm         = imm_ext;

        id_ex_d.ctrl        = ctrl;
    end


endmodule