package riscv_pkg;

    // ========================================================
    // Architectural Parameters
    // ========================================================

    localparam int unsigned XLEN            = 32;
    localparam int unsigned ILEN            = 32;
    localparam int unsigned NUM_REGS        = 32;
    localparam int unsigned REG_ADDR_W      = 5;
    localparam int unsigned NUM_BYTES       = XLEN / 8;


    // ========================================================
    // Common Architectural Types
    // ========================================================

    typedef logic [XLEN-1:0]                word_t;
    typedef logic [ILEN-1:0]                instr_t;
    typedef logic [XLEN-1:0]                addr_t;
    typedef logic [REG_ADDR_W-1:0]          reg_addr_t;

    typedef logic [6:0]                     opcode_t;
    typedef logic [6:0]                     funct7_t;
    typedef logic [2:0]                     funct3_t;

    typedef logic [NUM_BYTES-1:0]           byte_mask_t;

    
    // ========================================================
    // RISC-V Opcodes
    // ========================================================

    typedef enum logic [6:0] {
        OPC_LOAD      = 7'b0000011,
        OPC_MISC_MEM  = 7'b0001111,
        OPC_OP_IMM    = 7'b0010011,
        OPC_AUIPC     = 7'b0010111,
        OPC_STORE     = 7'b0100011,
        OPC_OP        = 7'b0110011,
        OPC_LUI       = 7'b0110111,
        OPC_BRANCH    = 7'b1100011,
        OPC_JALR      = 7'b1100111,
        OPC_JAL       = 7'b1101111,
        OPC_SYSTEM    = 7'b1110011
    } opcode_e;


    // ========================================================
    // RISC-V Opcodes
    // ========================================================

    typedef enum logic [3:0] {
        ALU_ADD       = 4'd0,
        ALU_SUB       = 4'd1,
        ALU_SLL       = 4'd2,
        ALU_SLT       = 4'd3,
        ALU_SLTU      = 4'd4,
        ALU_XOR       = 4'd5,
        ALU_SRL       = 4'd6,
        ALU_SRA       = 4'd7,
        ALU_OR        = 4'd8,
        ALU_AND       = 4'd9 
    } alu_op_e;


    // ========================================================
    // Immediate Types
    // ========================================================

    typedef enum logic [2:0]
    {
        IMM_I         = 3'd0,
        IMM_S         = 3'd1,
        IMM_B         = 3'd2,
        IMM_U         = 3'd3,
        IMM_J         = 3'd4
    } imm_sel_e;


    // ========================================================
    // ALU Operand Selection
    // ========================================================

    typedef enum logic [1:0]
    {
        OP_A_RS1      = 2'd0,
        OP_A_PC       = 2'd1,
        OP_A_ZERO     = 2'd2
    } op_a_sel_e;

    typedef enum logic
    {
        OP_B_RS2      = 1'd0,
        OP_B_IMM      = 1'd1
    } op_b_sel_e;


    // ========================================================
    // Writeback Selection
    // ========================================================

    typedef enum logic [1:0]
    {
        WB_ALU        = 2'd0,
        WB_MEM        = 2'd1,
        WB_PC4        = 2'd2
    } wb_sel_e;


    // ========================================================
    // Control-Flow Operations
    // ========================================================

    typedef enum logic [3:0]
    {
        CF_NONE       = 4'd0,
        CF_BEQ        = 4'd1,
        CF_BNE        = 4'd2,
        CF_BLT        = 4'd3,
        CF_BGE        = 4'd4,
        CF_BLTU       = 4'd5,
        CF_BGEU       = 4'd6,
        CF_JAL        = 4'd7,
        CF_JALR       = 4'd8
    } cf_op_e;


    // ========================================================
    // Memory Acccess Size
    // ========================================================

    typedef enum logic [1:0]
    {
        MEM_BYTE      = 2'd0,
        MEM_HALF      = 2'd1,
        MEM_WORD      = 2'd2
    } mem_size_e;


    // ========================================================
    // Forwarding Selection
    // ========================================================

    typedef enum logic [1:0] {
      FWD_NONE    = 2'b00,
      FWD_EX_MEM  = 2'b01,
      FWD_MEM_WB  = 2'b10
    } fwd_sel_e;


    // ========================================================
    // Decoded Instruction Control
    // ========================================================

    typedef struct packed {
        logic         illegal;

        logic         reg_write;
        logic         mem_read;
        logic         mem_write;

        logic         uses_rs1;
        logic         uses_rs2;

        logic         load_unsigned;

        alu_op_e      alu_op;
        imm_sel_e     imm_sel;
        op_a_sel_e    op_a_sel;
        op_b_sel_e    op_b_sel;
        wb_sel_e      wb_sel;
        cf_op_e       cf_op;
        mem_size_e    mem_size; 
    } ctrl_t;



    // ========================================================
    // Retirement metadata
    // ========================================================

    typedef struct packed {
        // Source reg info
        reg_addr_t      rs1_addr;
        reg_addr_t      rs2_addr;
        word_t          rs1_rdata;
        word_t          rs2_rdata;

        // Resolved next pc
        addr_t          next_pc;

        // Memory info
        addr_t          mem_addr;
        byte_mask_t     mem_rmask;
        byte_mask_t     mem_wmask;
        word_t          mem_rdata;
        word_t          mem_wdata;
    } retire_meta_t;


    // ========================================================
    // Instruction Fetch/Decode Bundle
    // ========================================================

    typedef struct packed {
        logic               valid;

        // Instruction info
        logic [XLEN-1:0]    pc;
        logic [XLEN-1:0]    pc_plus4;
        instr_t             instr;
    } if_id_t;


    // ========================================================
    // Instruction Decode/Execute Bundle
    // ========================================================

    typedef struct packed {
        logic               valid;

        // Instruction info
        addr_t              pc;
        addr_t              pc_plus4;
        instr_t             instr;

        // Register addresses
        reg_addr_t          rs1;
        reg_addr_t          rs2;
        reg_addr_t          rd;

        // Operand values
        word_t              rs1_data;
        word_t              rs2_data;
        word_t              imm;

        ctrl_t              ctrl;

        retire_meta_t       meta;
    } id_ex_t;


    // ========================================================
    // Execute/Memory Bundle
    // ========================================================

    typedef struct packed {
        logic               valid;

        // Instruction info
        addr_t              pc;
        addr_t              pc_plus4;   // carry to wb stage
        instr_t             instr;

        // Register addresses
        reg_addr_t          rd; // carry to wb stage for result

        // Operand values
        word_t              alu_result;
        word_t              store_data; // store rs2_data

        ctrl_t              ctrl;

        retire_meta_t       meta;
    } ex_mem_t;


    // ========================================================
    // Memory/Writeback Bundle
    // ========================================================

    typedef struct packed {
        logic               valid;

        // Instruction info
        addr_t              pc;
        addr_t              pc_plus4;   // carry to wb stage
        instr_t             instr;

        // Register addresses
        reg_addr_t          rd; // carry to wb stage for result

        // Operand values
        word_t              alu_result;
        word_t              mem_data;   // new, from data mem

        ctrl_t              ctrl;

        retire_meta_t       meta;
    } mem_wb_t;


    // ========================================================
    // Retirement / Formal Verification Interface
    // ========================================================

    typedef struct packed {
        // Retirement info
        logic         valid;
        logic [63:0]  order;
        instr_t       insn;

        // Exception / interrupt information
        logic         trap;
        logic         halt;
        logic         intr;

        // Source reg info
        reg_addr_t    rs1_addr;
        reg_addr_t    rs2_addr;
        word_t        rs1_rdata;
        word_t        rs2_rdata;
        
        // Destination reg info
        reg_addr_t    rd_addr;
        word_t        rd_wdata;

        // Program counter info
        addr_t        pc_rdata;
        addr_t        pc_wdata;

        // Memory info
        addr_t        mem_addr;
        byte_mask_t   mem_rmask;
        byte_mask_t   mem_wmask;
        word_t        mem_rdata;
        word_t        mem_wdata;
    } retire_t;


endpackage

