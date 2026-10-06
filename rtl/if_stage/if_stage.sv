module if_stage
    import riscv_pkg::*;
#(
    parameter logic [XLEN-1:0]  RESET_PC        = '0,
    parameter int unsigned      IMEM_DEPTH      = 256,
    parameter string            IMEM_INIT_FILE  = ""
)(
    input   logic               clk,
    input   logic               rst,
    
    // Pipeline control
    input   logic               pc_en,

    // Control-flow redirect from later stage
    input   logic               redirect_valid,
    input   logic [XLEN-1:0]    redirect_pc,

    // Output to IF/ID pipeline register
    output  if_id_t             if_id_d 
);

    logic [XLEN-1:0]            pc;
    logic [XLEN-1:0]            pc_plus4;
    logic [XLEN-1:0]            next_pc;

    instr_t                     instr;

    // --------------------------------------------------------
    // Next-PC logic
    // --------------------------------------------------------

    assign pc_plus4 = pc + 'd4;

    assign next_pc  = (redirect_valid)
                    ? (redirect_pc)
                    : (pc_plus4);


    // --------------------------------------------------------
    // Program Counter
    // --------------------------------------------------------

    pc_reg #(
        .RESET_PC   (RESET_PC)
    ) u_pc_reg (
        .clk        (clk),
        .rst        (rst),
        .en         (pc_en),
        .next_pc    (next_pc),
        .pc         (pc)
    );


    // --------------------------------------------------------
    // Instruction Memory
    // --------------------------------------------------------

    instr_mem #(
        .DEPTH      (IMEM_DEPTH),
        .INIT_FILE  (IMEM_INIT_FILE)
    ) u_instr_mem (
        .addr       (pc),
        .instr      (instr)
    );


    // --------------------------------------------------------
    // IF -> ID Bundle
    // --------------------------------------------------------

    always_comb begin
       if_id_d.valid        = 1'b1;
       if_id_d.pc           = pc;
       if_id_d.pc_plus4     = pc_plus4;
       if_id_d.instr        = instr;
    end


endmodule

