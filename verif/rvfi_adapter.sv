module rvfi_adapter
    import riscv_pkg::*;
#(
    // NRET corresponds to max # of instr retired in a cycle
    localparam int unsigned NRET = 1
)(
    input  retire_t              rvfi,

    // Instruction metadata
    output [NRET        - 1 : 0] rvfi_valid,
    output [NRET *   64 - 1 : 0] rvfi_order,
    output [NRET * ILEN - 1 : 0] rvfi_insn,
    output [NRET        - 1 : 0] rvfi_trap,
    output [NRET        - 1 : 0] rvfi_halt,
    output [NRET        - 1 : 0] rvfi_intr,
    output [NRET * 2    - 1 : 0] rvfi_mode,
    output [NRET * 2    - 1 : 0] rvfi_ixl,

    // Integer Register Read/Write
    output [NRET *    5 - 1 : 0] rvfi_rs1_addr,
    output [NRET *    5 - 1 : 0] rvfi_rs2_addr,
    output [NRET * XLEN - 1 : 0] rvfi_rs1_rdata,
    output [NRET * XLEN - 1 : 0] rvfi_rs2_rdata,

    output [NRET *    5 - 1 : 0] rvfi_rd_addr,
    output [NRET * XLEN - 1 : 0] rvfi_rd_wdata,

    // Program Counter
    output [NRET * XLEN - 1 : 0] rvfi_pc_rdata,
    output [NRET * XLEN - 1 : 0] rvfi_pc_wdata,

    // Memory Access
    output [NRET * XLEN   - 1 : 0] rvfi_mem_addr,
    output [NRET * XLEN/8 - 1 : 0] rvfi_mem_rmask,
    output [NRET * XLEN/8 - 1 : 0] rvfi_mem_wmask,
    output [NRET * XLEN   - 1 : 0] rvfi_mem_rdata,
    output [NRET * XLEN   - 1 : 0] rvfi_mem_wdata
);

    // Instruction metadata
    assign rvfi_valid  =   rvfi.valid;
    assign rvfi_order  =   rvfi.order;
    assign rvfi_insn   =   rvfi.insn;
    assign rvfi_trap   =   rvfi.trap;
    assign rvfi_halt   =   rvfi.halt;
    assign rvfi_intr   =   rvfi.intr;
    assign rvfi_mode   =   rvfi.mode;
    assign rvfi_ixl    =   rvfi.ixl;

    // Integer Register Read/Write
    assign rvfi_rs1_addr   = rvfi.rs1_addr;
    assign rvfi_rs2_addr   = rvfi.rs2_addr;
    assign rvfi_rs1_rdata  = rvfi.rs1_rdata;
    assign rvfi_rs2_rdata  = rvfi.rs2_rdata;

    assign rvfi_rd_addr    = rvfi.rd_addr;
    assign rvfi_rd_wdata   = rvfi.rd_wdata;

    // Program Counter
    assign rvfi_pc_rdata   = rvfi.pc_rdata;
    assign rvfi_pc_wdata   = rvfi.pc_wdata;

    // Memory Access
    assign rvfi_mem_addr   = rvfi.mem_addr;
    assign rvfi_mem_rmask  = rvfi.mem_rmask;
    assign rvfi_mem_wmask  = rvfi.mem_wmask;
    assign rvfi_mem_rdata  = rvfi.mem_rdata;
    assign rvfi_mem_wdata  = rvfi.mem_wdata;

endmodule

