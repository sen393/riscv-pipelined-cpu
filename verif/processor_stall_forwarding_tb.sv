
module processor_stall_forwarding_tb;
    import riscv_pkg::*;

    timeunit 1ns;
    timeprecision 1ps;

    // --------------------------------------------------------
    // Clock and reset
    // --------------------------------------------------------

    logic clk = 1'b0;
    logic rst = 1'b1;

    always #5 clk = ~clk;

    // --------------------------------------------------------
    // Memory interfaces
    // --------------------------------------------------------

    mem_bus_if imem (
        .clk (clk),
        .rst (rst)
    );

    mem_bus_if dmem (
        .clk (clk),
        .rst (rst)
    );

    retire_t rvfi;
    logic fetch_error;
    logic data_access_fault;

    // --------------------------------------------------------
    // DUT
    // --------------------------------------------------------

    riscv_core_ifbus dut (
        .clk               (clk),
        .rst               (rst),
        .imem              (imem),
        .dmem              (dmem),
        .rvfi              (rvfi),
        .fetch_error       (fetch_error),
        .data_access_fault (data_access_fault)
    );

    // --------------------------------------------------------
    // Instruction bus
    // --------------------------------------------------------

    // No instruction responses in this test.
    // We preload the pipeline instead.
    assign imem.req_ready = 1'b1;
    assign imem.rsp_valid = 1'b0;
    assign imem.rsp_rdata = '0;
    assign imem.rsp_err   = 1'b0;

    // --------------------------------------------------------
    // Data memory
    // --------------------------------------------------------

    logic [7:0] response_delay;

    assign response_delay = 8'd8;

    mem_bus_memory_model #(
        .DEPTH_WORDS (64),
        .BASE_ADDR   (32'h0000_1000)
    ) u_dmem (
        .bus            (dmem),
        .response_delay (response_delay)
    );

    // --------------------------------------------------------
    // Pipeline preload bundles
    // --------------------------------------------------------

    id_ex_t  add_seed;
    ex_mem_t load_seed;
    mem_wb_t producer_seed;

    initial begin

        add_seed      = '0;
        load_seed     = '0;
        producer_seed = '0;

        // ----------------------------------------------------
        // Producer in WB: addi x5, x0, 42
        // ----------------------------------------------------

        producer_seed.valid          = 1'b1;
        producer_seed.pc             = 32'h0000_0000;
        producer_seed.pc_plus4       = 32'h0000_0004;
        producer_seed.instr          = 32'h02A0_0293;
        producer_seed.rd             = 5'd5;
        producer_seed.alu_result     = 32'd42;
        producer_seed.ctrl.reg_write = 1'b1;
        producer_seed.ctrl.wb_sel    = WB_ALU;
        producer_seed.meta.next_pc   = 32'h0000_0004;

        // ----------------------------------------------------
        // Stalled instruction in MEM: lw x6, 0(x1)
        // ----------------------------------------------------

        load_seed.valid          = 1'b1;
        load_seed.pc             = 32'h0000_0004;
        load_seed.pc_plus4       = 32'h0000_0008;
        load_seed.instr          = 32'h0000_A303;
        load_seed.rd             = 5'd6;
        load_seed.alu_result     = 32'h0000_1000;

        load_seed.ctrl.reg_write = 1'b1;
        load_seed.ctrl.mem_read  = 1'b1;
        load_seed.ctrl.mem_size  = MEM_WORD;
        load_seed.ctrl.wb_sel    = WB_MEM;
        load_seed.meta.next_pc   = 32'h0000_0008;

        // ----------------------------------------------------
        // Consumer in EX: add x7, x5, x8
        //
        // x5 is deliberately stale
        // x8 contains 2
        // Expected result: 42 + 2 = 44
        // ----------------------------------------------------

        add_seed.valid          = 1'b1;
        add_seed.pc             = 32'h0000_0008;
        add_seed.pc_plus4       = 32'h0000_000C;
        add_seed.instr          = 32'h0082_83B3;

        add_seed.rs1            = 5'd5;
        add_seed.rs2            = 5'd8;
        add_seed.rd             = 5'd7;

        add_seed.rs1_data       = 32'hDEAD_0005;
        add_seed.rs2_data       = 32'd2;

        add_seed.ctrl.uses_rs1  = 1'b1;
        add_seed.ctrl.uses_rs2  = 1'b1;
        add_seed.ctrl.reg_write = 1'b1;

        add_seed.ctrl.alu_op    = ALU_ADD;
        add_seed.ctrl.op_a_sel  = OP_A_RS1;
        add_seed.ctrl.op_b_sel  = OP_B_RS2;
        add_seed.ctrl.wb_sel    = WB_ALU;

        add_seed.meta.rs1_addr  = 5'd5;
        add_seed.meta.rs2_addr  = 5'd8;
        add_seed.meta.next_pc   = 32'h0000_000C;

        // ----------------------------------------------------
        // Reset and preload
        // ----------------------------------------------------

        repeat (3) @(negedge clk);

        // Load returns 99, independently of the ADD
        u_dmem.mem[0] = 32'd99;

        rst = 1'b0;

        // Simulation-only backdoor pipeline initialization
        // Apply between clock edges and release before
        // normal execution resumes

        force dut.u_id_ex_reg.id_ex_q = add_seed;
        force dut.u_ex_mem_reg.ex_mem_q = load_seed;
        force dut.u_mem_wb_reg.mem_wb_q = producer_seed;

        #1;

        release dut.u_id_ex_reg.id_ex_q;
        release dut.u_ex_mem_reg.ex_mem_q;
        release dut.u_mem_wb_reg.mem_wb_q;

        #1;

        // Make sure the pipeline was initialized correctly
        if (dut.id_ex_q.rs1_data !== 32'hDEAD_0005 ||
            dut.ex_mem_q.alu_result !== 32'h0000_1000 ||
            dut.mem_wb_q.alu_result !== 32'd42)
            $fatal(1, "Pipeline preload failed");

        $display("[SETUP] Pipeline initialized");
    end

    // --------------------------------------------------------
    // Snooping coverage
    // --------------------------------------------------------

    bit saw_snoop = 1'b0;
    bit checked_snoop = 1'b0;

    int unsigned stall_cycles = 0;
    int unsigned dmem_reqs = 0;
    int unsigned dmem_rsps = 0;

    always @(posedge clk) begin
        if (!rst) begin

            if (dut.mem_stall)
                stall_cycles <= stall_cycles + 1;

            // Verify that the required snooping condition
            // actually occurs in the complete processor
            if (dut.mem_stall &&
                !dut.id_ex_en &&
                dut.id_ex_q.valid &&
                dut.wb_reg_write &&
                dut.wb_rd_addr == 5'd5 &&
                dut.wb_rd_wdata == 32'd42 &&
                dut.id_ex_q.rs1_data == 32'hDEAD_0005) begin

                saw_snoop <= 1'b1;

                $display(
                    "[SNOOP] WB writes x5=42 while ID/EX is held"
                );
            end

            if (dmem.req_valid && dmem.req_ready) begin
                dmem_reqs <= dmem_reqs + 1;

                if (dmem.req_write ||
                    dmem.req_addr !== 32'h0000_1000)
                    $fatal(1, "Unexpected memory request");
            end

            if (dmem.rsp_valid && dmem.rsp_ready) begin
                dmem_rsps <= dmem_rsps + 1;

                if (dmem.rsp_err ||
                    dmem.rsp_rdata !== 32'd99)
                    $fatal(1, "Incorrect memory response");
            end
        end
    end

    // Verify operand capture AFTER the snooping clock edge
    always @(negedge clk) begin
        if (!rst && saw_snoop && !checked_snoop) begin

            if (dut.id_ex_q.rs1_data !== 32'd42)
                $fatal(1, "ID/EX did not capture x5=42");

            if (dut.mem_wb_q.valid)
                $fatal(1, "Old WB producer still present");

            if (dut.fwd_a_sel !== FWD_NONE)
                $fatal(1, "Expected WB forwarding to disappear");

            if (!dut.mem_stall)
                $fatal(1, "Load unexpectedly stopped stalling");

            checked_snoop = 1'b1;

            $display(
                "[PASS] Operand preserved after WB source disappeared"
            );
        end
    end

    // --------------------------------------------------------
    // Retirement scoreboard
    // --------------------------------------------------------

    int unsigned retired = 0;

    always @(posedge clk) begin
        if (!rst) begin

            if (fetch_error || data_access_fault)
                $fatal(1, "Unexpected memory error");

            if (rvfi.valid) begin

                if (rvfi.order !== 64'(retired))
                    $fatal(1, "Retirement order mismatch");

                case (retired)

                    0: begin
                        if (rvfi.pc_rdata !== 32'h0 ||
                            rvfi.rd_addr !== 5'd5 ||
                            rvfi.rd_wdata !== 32'd42)
                            $fatal(1, "Producer retirement failed");
                    end

                    1: begin
                        if (rvfi.pc_rdata !== 32'h4 ||
                            rvfi.rd_addr !== 5'd6 ||
                            rvfi.rd_wdata !== 32'd99)
                            $fatal(1, "Load retirement failed");
                    end

                    2: begin
                        if (rvfi.pc_rdata !== 32'h8 ||
                            rvfi.rd_addr !== 5'd7 ||
                            rvfi.rd_wdata !== 32'd44)
                            $fatal(1, "Consumer used stale operand");

                        if (rvfi.rs1_rdata !== 32'd42 ||
                            rvfi.rs2_rdata !== 32'd2)
                            $fatal(1, "Consumer source metadata wrong");
                    end

                    default:
                        $fatal(1, "Unexpected extra retirement");

                endcase

                $display(
                    "[RETIRE] order=%0d pc=%08h rd=x%0d data=%08h",
                    rvfi.order,
                    rvfi.pc_rdata,
                    rvfi.rd_addr,
                    rvfi.rd_wdata
                );

                retired <= retired + 1;
            end
        end
    end

    // --------------------------------------------------------
    // Final checks
    // --------------------------------------------------------

    initial begin : completion
        wait (retired == 3);

        repeat (8) @(negedge clk);

        if (!saw_snoop || !checked_snoop)
            $fatal(1, "Snooping scenario was not exercised");

        if (dmem_reqs != 1 || dmem_rsps != 1)
            $fatal(1, "Expected exactly one load transaction");

        if (stall_cycles < 8)
            $fatal(1, "Expected extended memory stall");

        $display(
            "[BUS] requests=%0d responses=%0d stalls=%0d",
            dmem_reqs, dmem_rsps, stall_cycles
        );

        $display("[PASS] CPU forwarding-under-stall test");
        $finish;
    end

    // --------------------------------------------------------
    // Timeout watchdog
    // --------------------------------------------------------

    initial begin : timeout_watchdog
        repeat (200) @(negedge clk);
        $fatal(1,
            "Timeout: only %0d/3 instructions retired",
            retired
        );
    end

endmodule
