module id_ex_reg
    import riscv_pkg::*;
(
    input   logic               clk,
    input   logic               rst,

    input   logic               flush,
    input   logic               en,

    input   logic               wb_reg_write,
    input   reg_addr_t          wb_rd_addr,
    input   word_t              wb_rd_wdata,

    input   id_ex_t             id_ex_d,
    output  id_ex_t             id_ex_q
);

    always_ff @( posedge clk ) begin
        if (rst)
            id_ex_q <= '0; 
        else if (flush)
            id_ex_q <= '0;
        else if (en)
            id_ex_q <= id_ex_d;
        else begin
            if (id_ex_q.valid && wb_reg_write &&
                (wb_rd_addr != '0)) begin

                // Refresh source operations from WB while holding
                // the instruction during a mem stall

                if (id_ex_q.ctrl.uses_rs1 &&
                    (id_ex_q.rs1 == wb_rd_addr))
                    id_ex_q.rs1_data <= wb_rd_wdata;

                if (id_ex_q.ctrl.uses_rs2 &&
                    (id_ex_q.rs2 == wb_rd_addr))
                    id_ex_q.rs2_data <= wb_rd_wdata;
            end
        end
    end

endmodule

