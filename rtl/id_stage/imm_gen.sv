module imm_gen
    import riscv_pkg::*;
(
    input   imm_sel_e           imm_sel,
    input   instr_t             instr,
    output  word_t              imm_ext
);

    always_comb begin
        case (imm_sel)
            IMM_I: imm_ext = { {20{instr[31]}}, instr[31:20] };                // I-type
            IMM_S: imm_ext = { {20{instr[31]}}, instr[31:25], instr[11:7] };   // S-type
            IMM_B: imm_ext = { {20{instr[31]}}, instr[7],     instr[30:25], instr[11:8], 1'b0 }; // B-type
            IMM_J: imm_ext = { {12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0 };   // J-type
            IMM_U: imm_ext = { instr[31:12], 12'b0 };                          // U-type
            default: imm_ext = '0;
        endcase
    end

endmodule

