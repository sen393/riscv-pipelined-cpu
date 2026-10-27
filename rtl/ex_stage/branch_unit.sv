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

    // --------------------------------------------------------
    // Parallel branch comparisons
    // --------------------------------------------------------

    logic [3:0] byte_eq;
    logic [3:0] byte_lt;

    logic rs_eq;
    logic rs_lt_unsigned;
    logic rs_lt_signed;

    // Four parallel 8-bit comparisons
    for (genvar i = 0; i < 4; i++) begin : gen_compare
        assign byte_eq[i] =
            rs1_data[i*8 +: 8] == rs2_data[i*8 +: 8];

        assign byte_lt[i] =
            rs1_data[i*8 +: 8] < rs2_data[i*8 +: 8];
    end

    // Full equality comparison
    assign rs_eq = &byte_eq;

    // Unsigned comparison: most significant byte has priority
    assign rs_lt_unsigned =
        byte_lt[3] ||
        (byte_eq[3] && byte_lt[2]) ||
        (byte_eq[3] && byte_eq[2] && byte_lt[1]) ||
        (byte_eq[3] && byte_eq[2] && byte_eq[1] && byte_lt[0]);

    // Signed comparison
    assign rs_lt_signed =
        (rs1_data[31] != rs2_data[31])
            ? rs1_data[31]
            : rs_lt_unsigned;

    always_comb begin
        // Set defaults
        redirect_valid  = '0;
        redirect_pc     = '0;

        case (cf_op)

            CF_NONE     : begin
                redirect_valid  = 1'b0;
                redirect_pc     = '0;
            end

            CF_BEQ: begin
                redirect_valid = rs_eq;
                redirect_pc    = pc + imm;
            end

            CF_BNE: begin
                redirect_valid = !rs_eq;
                redirect_pc    = pc + imm;
            end

            CF_BLT: begin
                redirect_valid = rs_lt_signed;
                redirect_pc    = pc + imm;
            end

            CF_BGE: begin
                redirect_valid = !rs_lt_signed;
                redirect_pc    = pc + imm;
            end

            CF_BLTU: begin
                redirect_valid = rs_lt_unsigned;
                redirect_pc    = pc + imm;
            end

            CF_BGEU: begin
                redirect_valid = !rs_lt_unsigned;
                redirect_pc    = pc + imm;
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

