module decoder
    import riscv_pkg::*;
(
    input   instr_t     instr,
    output  ctrl_t      ctrl
);

    opcode_e    opcode;
    funct7_t    funct7;
    funct3_t    funct3;

    assign opcode = opcode_e'(instr[6:0]);
    assign funct7 = funct7_t'(instr[31:25]);
    assign funct3 = funct3_t'(instr[14:12]);

    always_comb begin

        // Safe defaults
        ctrl            = '0;
        ctrl.illegal    = 1'b1;
        ctrl.alu_op     = ALU_ADD;
        ctrl.imm_sel    = IMM_I;
        ctrl.op_a_sel   = OP_A_RS1;
        ctrl.op_b_sel   = OP_B_RS2;
        ctrl.wb_sel     = WB_ALU;
        ctrl.cf_op      = CF_NONE;
        ctrl.mem_size   = MEM_WORD;

        case (opcode)

            OPC_OP          : begin
                ctrl.uses_rs1   = 1'b1;
                ctrl.uses_rs2   = 1'b1;

                ctrl.op_a_sel   = OP_A_RS1;
                ctrl.op_b_sel   = OP_B_RS2;
                ctrl.wb_sel     = WB_ALU;

                case (funct3)
                    // ADD/SUB
                    3'b000  : begin
                        case (funct7)
                            7'b0000000  : begin
                                ctrl.illegal    = 1'b0;
                                ctrl.reg_write  = 1'b1;
                                ctrl.alu_op     = ALU_ADD;
                            end
                            7'b0100000  : begin
                                ctrl.illegal    = 1'b0;
                                ctrl.reg_write  = 1'b1;
                                ctrl.alu_op     = ALU_SUB;
                            end
                            default: ;
                        endcase
                    end

                    // SLL
                    3'b001  : begin
                        if (funct7 == 7'b0000000) begin
                            ctrl.illegal    = 1'b0;
                            ctrl.reg_write  = 1'b1;
                            ctrl.alu_op     = ALU_SLL;
                        end
                    end

                    // SLT
                    3'b010  : begin
                        if (funct7 == 7'b0000000) begin
                            ctrl.illegal    = 1'b0;
                            ctrl.reg_write  = 1'b1;
                            ctrl.alu_op     = ALU_SLT;
                        end
                    end

                    // SLTU
                    3'b011  : begin
                        if (funct7 == 7'b0000000) begin
                            ctrl.illegal    = 1'b0;
                            ctrl.reg_write  = 1'b1;
                            ctrl.alu_op     = ALU_SLTU;
                        end
                    end

                    // XOR
                    3'b100  : begin
                        if (funct7 == 7'b0000000) begin
                            ctrl.illegal    = 1'b0;
                            ctrl.reg_write  = 1'b1;
                            ctrl.alu_op     = ALU_XOR;
                        end
                    end

                    // SRL/SRA
                    3'b101  : begin
                        case (funct7)
                            7'b0000000  : begin
                                ctrl.illegal    = 1'b0;
                                ctrl.reg_write  = 1'b1;
                                ctrl.alu_op     = ALU_SRL;
                            end
                            7'b0100000  : begin
                                ctrl.illegal    = 1'b0;
                                ctrl.reg_write  = 1'b1;
                                ctrl.alu_op     = ALU_SRA;
                            end
                            default: ;
                        endcase
                    end

                    // OR
                    3'b110  : begin
                        if (funct7 == 7'b0000000) begin
                            ctrl.illegal    = 1'b0;
                            ctrl.reg_write  = 1'b1;
                            ctrl.alu_op     = ALU_OR;
                        end
                    end

                    // AND
                    3'b111  : begin
                        if (funct7 == 7'b0000000) begin
                            ctrl.illegal    = 1'b0;
                            ctrl.reg_write  = 1'b1;
                            ctrl.alu_op     = ALU_AND;
                        end
                    end
                    default: ;
                endcase
            end

            OPC_OP_IMM      : begin
                ctrl.uses_rs1   = 1'b1;

                ctrl.imm_sel    = IMM_I;
                ctrl.op_a_sel   = OP_A_RS1;
                ctrl.op_b_sel   = OP_B_IMM;
                ctrl.wb_sel     = WB_ALU;

                case (funct3)
                    // ADDI
                    3'b000  : begin
                        ctrl.illegal    = 1'b0;
                        ctrl.reg_write  = 1'b1;
                        ctrl.alu_op     = ALU_ADD;
                    end

                    // SLLI
                    3'b001  : begin
                        if (funct7 == 7'b0000000) begin
                            ctrl.illegal    = 1'b0;
                            ctrl.reg_write  = 1'b1;
                            ctrl.alu_op     = ALU_SLL;
                        end
                    end

                    // SLTI
                    3'b010  : begin
                        ctrl.illegal    = 1'b0;
                        ctrl.reg_write  = 1'b1;
                        ctrl.alu_op     = ALU_SLT;
                    end

                    // SLTIU
                    3'b011  : begin
                        ctrl.illegal    = 1'b0;
                        ctrl.reg_write  = 1'b1;
                        ctrl.alu_op     = ALU_SLTU;
                    end

                    // XORI
                    3'b100  : begin
                        ctrl.illegal    = 1'b0;
                        ctrl.reg_write  = 1'b1;
                        ctrl.alu_op     = ALU_XOR;
                    end

                    // SRLI/SRAI
                    3'b101  : begin
                        case (funct7)
                            7'b0000000  : begin
                                ctrl.illegal    = 1'b0;
                                ctrl.reg_write  = 1'b1;
                                ctrl.alu_op     = ALU_SRL;
                            end
                            7'b0100000  : begin
                                ctrl.illegal    = 1'b0;
                                ctrl.reg_write  = 1'b1;
                                ctrl.alu_op     = ALU_SRA;
                            end
                            default: ;
                        endcase
                    end

                    // ORI
                    3'b110  : begin
                        ctrl.illegal    = 1'b0;
                        ctrl.reg_write  = 1'b1;
                        ctrl.alu_op     = ALU_OR;
                    end

                    // ANDI
                    3'b111  : begin
                        ctrl.illegal    = 1'b0;
                        ctrl.reg_write  = 1'b1;
                        ctrl.alu_op     = ALU_AND;
                    end
                    default: ;
                endcase
            end

            OPC_LOAD        : begin
                ctrl.uses_rs1   = 1'b1;
                ctrl.mem_read   = 1'b1;

                ctrl.imm_sel    = IMM_I;

                ctrl.op_a_sel   = OP_A_RS1;
                ctrl.op_b_sel   = OP_B_IMM;

                ctrl.alu_op     = ALU_ADD;
                ctrl.wb_sel     = WB_MEM;

                case (funct3)
                    // LB
                    3'b000: begin
                        ctrl.illegal        = 1'b0;
                        ctrl.reg_write      = 1'b1;
                        ctrl.mem_size       = MEM_BYTE;
                        ctrl.load_unsigned  = 1'b0;
                    end
                    // LH
                    3'b001: begin
                        ctrl.illegal        = 1'b0;
                        ctrl.reg_write      = 1'b1;
                        ctrl.mem_size       = MEM_HALF;
                        ctrl.load_unsigned  = 1'b0;
                    end
                    // LW
                    3'b010: begin
                        ctrl.illegal        = 1'b0;
                        ctrl.reg_write      = 1'b1;
                        ctrl.mem_size       = MEM_WORD;
                        ctrl.load_unsigned  = 1'b0;
                    end
                    // LBU
                    3'b100: begin
                        ctrl.illegal        = 1'b0;
                        ctrl.reg_write      = 1'b1;
                        ctrl.mem_size       = MEM_BYTE;
                        ctrl.load_unsigned  = 1'b1;
                    end
                    // LHU
                    3'b101: begin
                        ctrl.illegal        = 1'b0;
                        ctrl.reg_write      = 1'b1;
                        ctrl.mem_size       = MEM_HALF;
                        ctrl.load_unsigned  = 1'b1;
                    end
                    default: ;
                endcase
            end

            OPC_STORE       : begin
                ctrl.uses_rs1   = 1'b1;
                ctrl.uses_rs2   = 1'b1;
                ctrl.mem_write  = 1'b1;

                ctrl.imm_sel    = IMM_S;

                ctrl.op_a_sel   = OP_A_RS1;
                ctrl.op_b_sel   = OP_B_IMM;

                ctrl.alu_op     = ALU_ADD;               

                case (funct3)
                    // SB
                    3'b000: begin
                        ctrl.illegal    = 1'b0;
                        ctrl.mem_size   = MEM_BYTE;
                    end
                    // SH
                    3'b001: begin
                        ctrl.illegal    = 1'b0;
                        ctrl.mem_size   = MEM_HALF;
                    end
                    // SW
                    3'b010: begin
                        ctrl.illegal    = 1'b0;
                        ctrl.mem_size   = MEM_WORD;
                    end
                    default: ;
                endcase
            end

            OPC_LUI         : begin
                ctrl.illegal    = 1'b0;
                ctrl.reg_write  = 1'b1;

                ctrl.imm_sel    = IMM_U;

                ctrl.op_a_sel   = OP_A_ZERO;
                ctrl.op_b_sel   = OP_B_IMM;

                ctrl.alu_op     = ALU_ADD;
                ctrl.wb_sel     = WB_ALU;
            end

            OPC_AUIPC       : begin
                ctrl.illegal    = 1'b0;
                ctrl.reg_write  = 1'b1;

                ctrl.imm_sel    = IMM_U;

                ctrl.op_a_sel   = OP_A_PC;
                ctrl.op_b_sel   = OP_B_IMM;

                ctrl.alu_op     = ALU_ADD;
                ctrl.wb_sel     = WB_ALU;
            end
            
            OPC_BRANCH      : begin
                ctrl.uses_rs1   = 1'b1;
                ctrl.uses_rs2   = 1'b1;

                ctrl.imm_sel    = IMM_B;

                // Compute branch target = PC + immediate
                ctrl.op_a_sel   = OP_A_PC;
                ctrl.op_b_sel   = OP_B_IMM;
                ctrl.alu_op     = ALU_ADD;

                case (funct3)
                    // BEQ
                    3'b000: begin
                        ctrl.illegal    = 1'b0;
                        ctrl.cf_op      = CF_BEQ;
                    end
                    // BNE
                    3'b001: begin
                        ctrl.illegal    = 1'b0;
                        ctrl.cf_op      = CF_BNE;
                    end
                    // BLT
                    3'b100: begin
                        ctrl.illegal    = 1'b0;
                        ctrl.cf_op      = CF_BLT;
                    end
                    // BGE
                    3'b101: begin
                        ctrl.illegal    = 1'b0;
                        ctrl.cf_op      = CF_BGE;
                    end
                    // BLTU
                    3'b110: begin
                        ctrl.illegal    = 1'b0;
                        ctrl.cf_op      = CF_BLTU;
                    end
                    // BGEU
                    3'b111: begin
                        ctrl.illegal    = 1'b0;
                        ctrl.cf_op      = CF_BGEU;
                    end
                    default: ;
                endcase
            end

            OPC_JALR        : begin
                ctrl.uses_rs1   = 1'b1;

                ctrl.imm_sel    = IMM_I;

                ctrl.op_a_sel   = OP_A_RS1;
                ctrl.op_b_sel   = OP_B_IMM;
                ctrl.alu_op     = ALU_ADD;

                ctrl.wb_sel     = WB_PC4;
                ctrl.cf_op      = CF_JALR;

                if (funct3 == 3'b000) begin
                    ctrl.illegal    = 1'b0;
                    ctrl.reg_write  = 1'b1;
                end
            end

            OPC_JAL         : begin
                ctrl.illegal    = 1'b0;
                ctrl.reg_write  = 1'b1;

                ctrl.imm_sel    = IMM_J;

                ctrl.op_a_sel   = OP_A_PC;
                ctrl.op_b_sel   = OP_B_IMM;
                ctrl.alu_op     = ALU_ADD;

                ctrl.wb_sel     = WB_PC4;
                ctrl.cf_op      = CF_JAL;
            end

            // Not implemented, until after first version
            OPC_SYSTEM      : begin
            end
            OPC_MISC_MEM    : begin
                case (funct3)
                    3'b000  : begin
                        // FENCE
                        // no architectural side effects for this core
                        ctrl.illegal    = 1'b0;
                    end

                    default : begin
                        // Unsupported instructions
                    end
                endcase
            end
            default: ;
        endcase

        // Illegal function cleanup
        if (ctrl.illegal) begin
            ctrl.reg_write  = 1'b0;
            ctrl.mem_read   = 1'b0;
            ctrl.mem_write  = 1'b0;
            ctrl.uses_rs1   = 1'b0;
            ctrl.uses_rs2   = 1'b0;
            ctrl.cf_op      = CF_NONE;
        end

    end

endmodule

