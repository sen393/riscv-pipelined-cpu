module instr_mem
    import riscv_pkg::*;
#(
        parameter int unsigned  DEPTH = 256,
        parameter string        INIT_FILE = ""
)(
    input   logic [XLEN-1:0]    addr,
    output  instr_t             instr
);

    localparam int unsigned ADDR_WIDTH = $clog2(DEPTH);

    logic [ADDR_WIDTH-1:0] word_addr;

    // Divide addr by 4
    assign word_addr = addr[ADDR_WIDTH+1:2];

    /*
    `ifdef RISCV_FORMAL
        // --------------------------------------------------------
        // Formal Verification Instr Mem
        // --------------------------------------------------------

        (* anyconst *) logic [DEPTH * ILEN - 1 : 0] formal_mem;

        // Select instruction at requested word addr 
        assign instr = formal_mem[word_addr*ILEN +: ILEN];

    `else

        // --------------------------------------------------------
        // Simulation / FPGA Instr Mem
        // --------------------------------------------------------

            instr_t mem [0:DEPTH-1];

            // Read instructions from given file path INIT_FILE
            initial begin
                if (INIT_FILE != "")
                    $readmemh(INIT_FILE, mem);
            end

            assign instr = mem[word_addr];

    `endif
    */

    `ifdef RISCV_FORMAL

        formal_instr_rom u_formal_instr_rom (
            .addr  (addr),
            .instr (instr)
        );

    `else

        instr_t mem [0:DEPTH-1];

        initial begin
            if (INIT_FILE != "")
                $readmemh(INIT_FILE, mem);
        end

        assign instr = mem[word_addr];

    `endif

endmodule

