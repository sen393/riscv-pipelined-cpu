module ex_stage
    import riscv_pkg::*;
(
    // From ID/EX pipeline reg
    input   id_ex_t     id_ex_q,

    // Forwarding control from hazard unit
    input   fwd_sel_e   fwd_a_sel,
    input   fwd_sel_e   fwd_b_sel,

    // Forwarding data
    input   word_t      ex_mem_fwd_data,
    input   word_t      mem_wb_fwd_data,

    // To EX/MEM pipeline reg
    output  ex_mem_t    ex_mem_d,

    // Control-flow logic back to fetch
    output  logic       redirect_valid, 
    output  addr_t      redirect_pc,

    // Exception detected in EX
    output  logic       instr_addr_misaligned,
    output  logic       data_addr_misaligned
);

    // --------------------------------------------------------
    // Forwarded signals
    // --------------------------------------------------------

    word_t          rs1_fwd;
    word_t          rs2_fwd;

    // --------------------------------------------------------
    // ALU operands
    // --------------------------------------------------------

    word_t          operand_a;
    word_t          operand_b;
    word_t          alu_result;


    // --------------------------------------------------------
    // Input data forwarding selection
    // --------------------------------------------------------

    always_comb begin

        // ----------------------------------------------------
        // rs1 forwarding mux
        // ----------------------------------------------------

        case (fwd_a_sel)
            FWD_EX_MEM  : rs1_fwd = ex_mem_fwd_data;
            FWD_MEM_WB  : rs1_fwd = mem_wb_fwd_data;
            FWD_NONE    : rs1_fwd = id_ex_q.rs1_data;
            default     : rs1_fwd = id_ex_q.rs1_data;
        endcase


        // ----------------------------------------------------
        // rs2 forwarding mux
        // ----------------------------------------------------

        case (fwd_b_sel)
            FWD_EX_MEM  : rs2_fwd = ex_mem_fwd_data;
            FWD_MEM_WB  : rs2_fwd = mem_wb_fwd_data;
            FWD_NONE    : rs2_fwd = id_ex_q.rs2_data;
            default     : rs2_fwd = id_ex_q.rs2_data;
        endcase

    end
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
            OP_A_RS1    : operand_a = rs1_fwd;
            OP_A_PC     : operand_a = id_ex_q.pc;
            OP_A_ZERO   : operand_a = '0;
            default     : operand_a = '0;
        endcase

        case (id_ex_q.ctrl.op_b_sel)
            OP_B_RS2    : operand_b = rs2_fwd;
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
        .rs1_data       (rs1_fwd),
        .rs2_data       (rs2_fwd),
        .imm            (id_ex_q.imm),
        .cf_op          (id_ex_q.ctrl.cf_op),

        .redirect_valid (branch_redirect_valid),
        .redirect_pc    (branch_redirect_pc)
    );


    // --------------------------------------------------------
    // Instruction address alignment check
    // --------------------------------------------------------

    assign instr_addr_misaligned =
        id_ex_q.valid           &&
        branch_redirect_valid   &&
        (branch_redirect_pc[1:0] != 2'b00);


    // --------------------------------------------------------
    // Data address alignment check
    // --------------------------------------------------------

    always_comb begin
        data_addr_misaligned = 1'b0;

        if (id_ex_q.valid &&
            (id_ex_q.ctrl.mem_read || id_ex_q.ctrl.mem_write)) begin
            
            case (id_ex_q.ctrl.mem_size)
                MEM_BYTE    : data_addr_misaligned = 1'b0;
                MEM_HALF    : data_addr_misaligned = alu_result[0];
                MEM_WORD    : data_addr_misaligned = |alu_result[1:0];
                default     : data_addr_misaligned = 1'b0;
            endcase

        end
    end



    // --------------------------------------------------------
    // Control-flow redirect
    // --------------------------------------------------------

    assign redirect_valid   =   id_ex_q.valid           &&
                                branch_redirect_valid   &&
                                !instr_addr_misaligned;

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
        ex_mem_d.store_data = rs2_fwd;

        ex_mem_d.ctrl       = id_ex_q.ctrl;

        // ----------------------------------------------------
        // Retirement Metadata
        // ----------------------------------------------------

        if (id_ex_q.valid) begin
            // Propogate existing metadata from ID
            ex_mem_d.meta       = id_ex_q.meta;
            
            // Capture resolved rs1/rs2 data after fwd
            ex_mem_d.meta.rs1_rdata = (id_ex_q.ctrl.uses_rs1) ? rs1_fwd : '0;
            ex_mem_d.meta.rs2_rdata = (id_ex_q.ctrl.uses_rs2) ? rs2_fwd : '0;

            // Capture next PC
            ex_mem_d.meta.next_pc   = (branch_redirect_valid) ? branch_redirect_pc : id_ex_q.pc_plus4;

            // ------------------------------------------------
            // EX-stage exceptions
            // ------------------------------------------------

            if (instr_addr_misaligned)
                ex_mem_d.ctrl.exc_kind  = EXC_INSTR_MISALIGNED;

            else if (data_addr_misaligned) begin
                ex_mem_d.ctrl.exc_kind  =
                    id_ex_q.ctrl.mem_read   ?
                    EXC_LOAD_MISALIGNED     :
                    EXC_STORE_MISALIGNED;
            end


            if (instr_addr_misaligned || data_addr_misaligned) begin
                // Must not commit reg or mem changes
                ex_mem_d.ctrl.reg_write = 1'b0;
                ex_mem_d.ctrl.mem_read  = 1'b0;
                ex_mem_d.ctrl.mem_write = 1'b0;
            end
        end
    end


endmodule

