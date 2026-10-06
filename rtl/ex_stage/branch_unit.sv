module branch_unit
    import riscv_pkg::*;
(
    input   addr_t      pc,
    input   word_t      rs1_data,
    input   word_t      rs2_data,
    input   word_t      imm,
    input   cf_op_e     cf_op,

    output  logic       redirect_valid,
    output  addr_t      redirect_pc
);

    always_comb begin
        // Set defaults
        redirect_valid  = '0;
        redirect_pc     = '0;

        case (cf_op)

            CF_NONE     : begin
                redirect_valid  = 1'b0;
                redirect_pc     = '0;
            end

            CF_BEQ      : begin
                redirect_valid  = (rs1_data == rs2_data);
                redirect_pc     = (pc + imm);
            end

            CF_BNE      : begin
                redirect_valid  = (rs1_data != rs2_data);
                redirect_pc     = (pc + imm);
            end

            CF_BLT      : begin
                redirect_valid  = ($signed(rs1_data) <  $signed(rs2_data));
                redirect_pc     = (pc + imm);
            end

            CF_BGE      : begin
                redirect_valid  = ($signed(rs1_data) >= $signed(rs2_data));
                redirect_pc     = (pc + imm);
            end

            CF_BLTU     : begin
                redirect_valid  = (rs1_data <  rs2_data);
                redirect_pc     = (pc + imm);
            end

            CF_BGEU     : begin
                redirect_valid  = (rs1_data >= rs2_data);
                redirect_pc     = (pc + imm);
            end

            CF_JAL      : begin
                redirect_valid  = 1'b1;
                redirect_pc     = (pc + imm);
            end

            CF_JALR     : begin
                redirect_valid  = 1'b1;
                redirect_pc     = (rs1_data + imm) & 32'hFFFF_FFFE;
            end

            default     : begin
                redirect_valid  = 1'b0;
                redirect_pc     = '0;
            end

        endcase
    end

endmodule

