
module id_ex_hold_tb;
    import riscv_pkg::*;

    timeunit 1ns;
    timeprecision 1ps;

    logic clk = 1'b0;
    logic rst;
    logic flush;
    logic en;

    logic       wb_reg_write;
    reg_addr_t  wb_rd_addr;
    word_t      wb_rd_wdata;

    id_ex_t id_ex_d;
    id_ex_t id_ex_q;

    always #5 clk = ~clk;

    id_ex_reg dut (
        .clk          (clk),
        .rst          (rst),
        .flush        (flush),
        .en           (en),

        .wb_reg_write (wb_reg_write),
        .wb_rd_addr   (wb_rd_addr),
        .wb_rd_wdata  (wb_rd_wdata),

        .id_ex_d      (id_ex_d),
        .id_ex_q      (id_ex_q)
    );

    // --------------------------------------------------------
    // Test utilities
    // --------------------------------------------------------

    task automatic tick();
        @(posedge clk);
        #1;
    endtask

    task automatic check_operands(
        input word_t expected_rs1,
        input word_t expected_rs2
    );
        if (id_ex_q.rs1_data !== expected_rs1 ||
            id_ex_q.rs2_data !== expected_rs2)
            $fatal(1,
                "Operand mismatch: rs1=%08h rs2=%08h",
                id_ex_q.rs1_data,
                id_ex_q.rs2_data
            );
    endtask

    // --------------------------------------------------------
    // Directed test
    // --------------------------------------------------------

    initial begin
        rst = 1'b1;
        flush = 1'b0;
        en = 1'b0;

        wb_reg_write = 1'b0;
        wb_rd_addr = '0;
        wb_rd_wdata = '0;

        id_ex_d = '0;

        tick();

        // Load an instruction with intentionally stale operands
        rst = 1'b0;
        en = 1'b1;

        id_ex_d.valid = 1'b1;
        id_ex_d.pc = 32'h0000_0010;
        id_ex_d.rs1 = 5'd5;
        id_ex_d.rs2 = 5'd6;
        id_ex_d.rs1_data = 32'hDEAD_0005;
        id_ex_d.rs2_data = 32'hDEAD_0006;

        id_ex_d.ctrl.uses_rs1 = 1'b1;
        id_ex_d.ctrl.uses_rs2 = 1'b1;

        tick();
        check_operands(32'hDEAD_0005, 32'hDEAD_0006);

        // ----------------------------------------------------
        // TEST 1: WB updates rs1 during a hold
        // ----------------------------------------------------

        en = 1'b0;

        wb_reg_write = 1'b1;
        wb_rd_addr = 5'd5;
        wb_rd_wdata = 32'd42;

        tick();

        check_operands(32'd42, 32'hDEAD_0006);
        $display("[PASS] RS1 writeback snooping");

        // Remove WB source; operand must remain preserved
        wb_reg_write = 1'b0;
        wb_rd_wdata = '0;

        repeat (4) tick();

        check_operands(32'd42, 32'hDEAD_0006);
        $display("[PASS] Operand survives extended stall");

        // ----------------------------------------------------
        // TEST 2: WB updates rs2 during a hold
        // ----------------------------------------------------

        wb_reg_write = 1'b1;
        wb_rd_addr = 5'd6;
        wb_rd_wdata = 32'd99;

        tick();

        check_operands(32'd42, 32'd99);
        $display("[PASS] RS2 writeback snooping");

        // ----------------------------------------------------
        // TEST 3: Unrelated WB must not change operands
        // ----------------------------------------------------

        wb_rd_addr = 5'd7;
        wb_rd_wdata = 32'd123;

        tick();

        check_operands(32'd42, 32'd99);
        $display("[PASS] Unrelated writeback ignored");

        // ----------------------------------------------------
        // TEST 4: Writes to x0 must be ignored
        // ----------------------------------------------------

        wb_rd_addr = 5'd0;
        wb_rd_wdata = 32'hFFFF_FFFF;

        tick();

        check_operands(32'd42, 32'd99);
        $display("[PASS] Zero register ignored");

        // ----------------------------------------------------
        // TEST 5: Held instruction metadata is preserved
        // ----------------------------------------------------

        if (!id_ex_q.valid ||
            id_ex_q.pc !== 32'h0000_0010 ||
            id_ex_q.rs1 !== 5'd5 ||
            id_ex_q.rs2 !== 5'd6)
            $fatal(1, "Held instruction was corrupted");

        $display("[PASS] Instruction metadata preserved");

        // ----------------------------------------------------
        // TEST 6: Flush overrides hold and WB snooping
        // ----------------------------------------------------

        flush = 1'b1;
        wb_rd_addr = 5'd5;
        wb_rd_wdata = 32'd777;

        tick();

        if (id_ex_q.valid !== 1'b0)
            $fatal(1, "Flush failed");

        $display("[PASS] Flush priority");

        $display("[PASS] ID/EX hold verification");
        $finish;
    end

endmodule
