module hazard_unit
    import riscv_pkg::*;
(
    input   id_ex_t     id_ex_d,    // instr currently in ID
    input   id_ex_t     id_ex_q,    // instr currently in EX
    input   ex_mem_t    ex_mem_q,   // possible producer
    input   mem_wb_t    mem_wb_q,   // possible producer (older)

    output  fwd_sel_e   fwd_a_sel,  // rs1 selector
    output  fwd_sel_e   fwd_b_sel,  // rs2 selector

    output  logic       stall
);

    // Check for new val in EX/MEM, else check MEM/WB, else default
    always_comb begin
        
        // Defaults: no forwarding
        fwd_a_sel   = FWD_NONE;
        fwd_b_sel   = FWD_NONE;
        stall       = '0;

        // --------------------------------------------------------
        // Stall logic
        // --------------------------------------------------------

        stall       =   id_ex_q.valid                       &&
                        id_ex_q.ctrl.reg_write              &&
                        (id_ex_q.ctrl.wb_sel == WB_MEM)     &&
                        (id_ex_q.rd != '0)                  &&
                        id_ex_d.valid                       &&
                        (
                            (id_ex_d.ctrl.uses_rs1 &&
                            (id_ex_q.rd == id_ex_d.rs1))    ||
                            (id_ex_d.ctrl.uses_rs2 &&
                            (id_ex_q.rd == id_ex_d.rs2))
                        );


        // --------------------------------------------------------
        // rs1 forwarding selection
        // --------------------------------------------------------

        if (
            id_ex_q.valid                       &&
            ex_mem_q.valid                      &&
            ex_mem_q.ctrl.reg_write             &&
            (ex_mem_q.ctrl.wb_sel != WB_MEM)    &&
            (ex_mem_q.rd != '0)                 &&
            (ex_mem_q.rd == id_ex_q.rs1)
        )
            fwd_a_sel = FWD_EX_MEM;
        else if (
            id_ex_q.valid                       &&
            mem_wb_q.valid                      &&
            mem_wb_q.ctrl.reg_write             &&
            (mem_wb_q.rd != '0)                 &&
            (mem_wb_q.rd == id_ex_q.rs1)
        )
            fwd_a_sel = FWD_MEM_WB;
        // else default: fwd not necessary


        // --------------------------------------------------------
        // rs2 forwarding selection
        // --------------------------------------------------------

        if (
            id_ex_q.valid                       &&
            ex_mem_q.valid                      &&
            ex_mem_q.ctrl.reg_write             &&
            (ex_mem_q.ctrl.wb_sel != WB_MEM)    &&
            (ex_mem_q.rd != '0)                 &&
            (ex_mem_q.rd == id_ex_q.rs2)
        )
            fwd_b_sel = FWD_EX_MEM;
        else if (
            id_ex_q.valid                       &&
            mem_wb_q.valid                      &&
            mem_wb_q.ctrl.reg_write             &&
            (mem_wb_q.rd != '0)                 &&
            (mem_wb_q.rd == id_ex_q.rs2)
        )
            fwd_b_sel = FWD_MEM_WB; 
        // else default: fwd not necessary

    end

endmodule

