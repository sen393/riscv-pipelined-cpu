module ex_stage
    import riscv_pkg::*;
(
    // From ID/EX pipeline reg
    input   id_ex_t     id_ex_q,

    // To EX/MEM pipeline reg
    output  ex_mem_t    ex_mem_d,

    // Control-flow logic back to fetch
   output   logic       redirect_valid, 
   output   addr_t      redirect_pc
);

    // --------------------------------------------------------
    // ALU operands
    // --------------------------------------------------------

    word_t          operand_a;
    word_t          operand_b;
    word_t          alu_result;


    // --------------------------------------------------------
    // Branch unit outputs
    // --------------------------------------------------------

    logic           branch_redirect_valid;
    addr_t          branch_redirect_pc;


    // --------------------------------------------------------
    // ALU operand select
    // --------------------------------------------------------

    always_comb begin

        case (id_ex_q.ctrl.op_a_sel)
            OP_A_RS1    : operand_a = id_ex_q.rs1_data;
            OP_A_PC     : operand_a = id_ex_q.pc;
            OP_A_ZERO   : operand_a = '0;
            default     : operand_a = '0;
        endcase

        case (id_ex_q.ctrl.op_b_sel)
            OP_B_RS2    : operand_b = id_ex_q.rs2_data;
            OP_B_IMM    : operand_b = id_ex_q.imm;
            default     : operand_b = '0;
        endcase

    end


    // --------------------------------------------------------
    // ALU
    // --------------------------------------------------------

    alu u_alu
    (
        .operand_a      (operand_a),
        .operand_b      (operand_b),
        .alu_op         (id_ex_q.ctrl.alu_op),

        .result         (alu_result)
    );


    // --------------------------------------------------------
    // Branch / Jump unit
    // --------------------------------------------------------

    branch_unit u_branch_unit
    (
        .pc             (id_ex_q.pc),
        .rs1_data       (id_ex_q.rs1_data),
        .rs2_data       (id_ex_q.rs2_data),
        .imm            (id_ex_q.imm),
        .cf_op          (id_ex_q.ctrl.cf_op),

        .redirect_valid (branch_redirect_valid),
        .redirect_pc    (branch_redirect_pc)
    );


    // --------------------------------------------------------
    // Control-flow redirect
    // --------------------------------------------------------

    assign redirect_valid   = id_ex_q.valid && branch_redirect_valid;
    assign redirect_pc      = branch_redirect_pc;


    // --------------------------------------------------------
    // EX -> MEM Bundle
    // --------------------------------------------------------

    always_comb begin
        // initialize
        ex_mem_d            = '0;

        ex_mem_d.valid      = id_ex_q.valid;

        ex_mem_d.pc         = id_ex_q.pc;
        ex_mem_d.pc_plus4   = id_ex_q.pc_plus4;
        ex_mem_d.instr      = id_ex_q.instr;

        ex_mem_d.rd         = id_ex_q.rd;

        ex_mem_d.alu_result = alu_result;
        ex_mem_d.store_data = id_ex_q.rs2_data;

        ex_mem_d.ctrl       = id_ex_q.ctrl;
    end


endmodule

