module alu
    import riscv_pkg::*;
(
    input   word_t      operand_a,
    input   word_t      operand_b,
    input   alu_op_e    alu_op,
    
    output  word_t      result
);

    always_comb begin
        case (alu_op)
            result = '0; // initialize result            

            ALU_ADD     : result = operand_a + operand_b;
            ALU_SUB     : result = operand_a - operand_b;

            ALU_SLT     : result = {31'd0, $signed(operand_a)
                                         < $signed(operand_b)};
            ALU_SLTU    : result = {31'd0,
                                    operand_a < operand_b};

            ALU_SLL     : result = operand_a <<  operand_b[4:0];
            ALU_SRL     : result = operand_a >>  operand_b[4:0];
            ALU_SRA     : result = $signed(operand_a) >>>
                                           operand_b[4:0];

            ALU_OR      : result = operand_a | operand_b;
            ALU_XOR     : result = operand_a ^ operand_b;
            ALU_AND     : result = operand_a & operand_b;
        endcase
    end

endmodule