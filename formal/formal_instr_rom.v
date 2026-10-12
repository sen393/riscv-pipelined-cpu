module formal_instr_rom (
    input  wire [31:0] addr,
    output wire [31:0] instr
);

    // 256 symbolic, constant instruction words
    (* anyconst *) reg [8191:0] formal_mem;

    // Select the instruction corresponding to the PC
    assign instr = formal_mem[{addr[9:2], 5'b00000} +: 32];

endmodule