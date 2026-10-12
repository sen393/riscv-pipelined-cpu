module processor_hazard_tb;
    import riscv_pkg::*;

    timeunit 1ns;
    timeprecision 1ps;

    localparam int unsigned CLK_PERIOD = 10;
    localparam int unsigned MAX_CYCLES = 200;
    localparam int unsigned NUM_TEST_INSTRS = 48;

    logic    clk;
    logic    rst;
    retire_t rvfi;

    int unsigned retire_count = 0;
    int unsigned stall_cycles = 0;
    int unsigned redirect_count = 0;
    int unsigned ex_a_count = 0;
    int unsigned ex_b_count = 0;
    int unsigned wb_a_count = 0;
    int unsigned wb_b_count = 0;
    bit saw_priority = 0;

    riscv_core #(
        .IMEM_INIT_FILE("../verif/programs/hazard.hex")
    ) u_dut (
        .clk  (clk),
        .rst  (rst),
        .rvfi (rvfi)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Initialize memory words used to detect wrong-path stores.
    initial begin
        rst = 1'b1;
        u_dut.u_mem_stage.u_data_mem.mem[34] = 32'hA5A5A5A5;
        u_dut.u_mem_stage.u_data_mem.mem[35] = 32'hB6B6B6B6;
        u_dut.u_mem_stage.u_data_mem.mem[36] = 32'hC7C7C7C7;
        u_dut.u_mem_stage.u_data_mem.mem[37] = 32'hD8D8D8D8;

        repeat (3) @(negedge clk);
        rst = 1'b0;
    end

    task automatic expect_retire(
        input addr_t     expected_pc,
        input addr_t     expected_next_pc,
        input reg_addr_t expected_rd,
        input word_t     expected_data
    );
        if (rvfi.pc_rdata !== expected_pc ||
            rvfi.pc_wdata !== expected_next_pc ||
            rvfi.rd_addr  !== expected_rd ||
            rvfi.rd_wdata !== expected_data) begin
            $fatal(1,
                "[RETIRE %0d] Expected pc=%08h -> %08h, x%0d=%08h; got pc=%08h -> %08h, x%0d=%08h",
                retire_count, expected_pc, expected_next_pc, expected_rd,
                expected_data, rvfi.pc_rdata, rvfi.pc_wdata, rvfi.rd_addr,
                rvfi.rd_wdata);
        end
    endtask

    task automatic expect_word_mem(
        input bit    is_store,
        input addr_t expected_addr,
        input word_t expected_data
    );
        if (rvfi.mem_addr !== expected_addr ||
            rvfi.mem_rmask !== (is_store ? 4'b0000 : 4'b1111) ||
            rvfi.mem_wmask !== (is_store ? 4'b1111 : 4'b0000) ||
            (is_store ? rvfi.mem_wdata : rvfi.mem_rdata) !== expected_data)
            $fatal(1, "[RETIRE %0d] Word memory metadata mismatch at pc=%08h",
                   retire_count, rvfi.pc_rdata);
    endtask

    initial begin
        wait (rst == 1'b0);

        repeat (MAX_CYCLES) begin
            @(negedge clk);

            // Internal microarchitectural coverage.
            if (u_dut.stall)
                stall_cycles++;
            if (u_dut.redirect_valid)
                redirect_count++;

            if (u_dut.id_ex_q.valid) begin
                if (u_dut.fwd_a_sel == FWD_EX_MEM) ex_a_count++;
                if (u_dut.fwd_b_sel == FWD_EX_MEM) ex_b_count++;
                if (u_dut.fwd_a_sel == FWD_MEM_WB) wb_a_count++;
                if (u_dut.fwd_b_sel == FWD_MEM_WB) wb_b_count++;

                // The instruction at PC=0x28 must use x6=9 from EX/MEM,
                // not the older x6=8 from MEM/WB.
                if (u_dut.id_ex_q.pc == 32'h00000028) begin
                    saw_priority = 1;
                    if (u_dut.fwd_a_sel !== FWD_EX_MEM)
                        $fatal(1, "Forwarding priority failure at PC=0x28");
                end
            end

            if (rvfi.valid) begin
                if (rvfi.order !== retire_count)
                    $fatal(1, "Retirement order mismatch at %0d", retire_count);
                if (rvfi.trap || rvfi.halt)
                    $fatal(1, "Unexpected exception at pc=%08h", rvfi.pc_rdata);

                // Architectural expectations for all 48 retired instructions.
                // Skipped PCs must never appear in this sequence.
                case (retire_count)
                     0: expect_retire(32'h00000000, 32'h00000004, 5'd1,  32'h00000080);
                     1: expect_retire(32'h00000004, 32'h00000008, 5'd2,  32'h00000005);
                     2: expect_retire(32'h00000008, 32'h0000000c, 5'd3,  32'h0000000c);
                     3: expect_retire(32'h0000000c, 32'h00000010, 5'd4,  32'h00000011);
                     4: expect_retire(32'h00000010, 32'h00000014, 5'd5,  32'h0000001d);
                     5: expect_retire(32'h00000014, 32'h00000018, 5'd6,  32'h00000001);
                     6: expect_retire(32'h00000018, 32'h0000001c, 5'd6,  32'h00000003);
                     7: expect_retire(32'h0000001c, 32'h00000020, 5'd7,  32'h00000007);
                     8: expect_retire(32'h00000020, 32'h00000024, 5'd6,  32'h00000008);
                     9: expect_retire(32'h00000024, 32'h00000028, 5'd6,  32'h00000009);
                    10: expect_retire(32'h00000028, 32'h0000002c, 5'd8,  32'h00000009);
                    11: expect_retire(32'h0000002c, 32'h00000030, 5'd0,  32'h00000000);
                    12: expect_retire(32'h00000030, 32'h00000034, 5'd9,  32'h00000001);
                    13: expect_retire(32'h00000034, 32'h00000038, 5'd0,  32'h00000000);
                    14: expect_retire(32'h00000038, 32'h0000003c, 5'd10, 32'h0000001d);
                    15: expect_retire(32'h0000003c, 32'h00000040, 5'd11, 32'h00000022);
                    16: expect_retire(32'h00000040, 32'h00000044, 5'd12, 32'h0000001d);
                    17: expect_retire(32'h00000044, 32'h00000048, 5'd13, 32'h00000022);
                    18: expect_retire(32'h00000048, 32'h0000004c, 5'd14, 32'h0000001d);
                    19: expect_retire(32'h0000004c, 32'h00000050, 5'd0,  32'h00000000);
                    20: expect_retire(32'h00000050, 32'h00000054, 5'd15, 32'h0000001d);
                    21: expect_retire(32'h00000054, 32'h00000058, 5'd16, 32'h00000003);
                    22: expect_retire(32'h00000058, 32'h0000005c, 5'd16, 32'h00000004);
                    23: expect_retire(32'h0000005c, 32'h00000060, 5'd0,  32'h00000000);
                    24: expect_retire(32'h00000060, 32'h0000006c, 5'd0,  32'h00000000);
                    25: expect_retire(32'h0000006c, 32'h00000070, 5'd18, 32'h0000000b);
                    26: expect_retire(32'h00000070, 32'h0000007c, 5'd19, 32'h00000074);
                    27: expect_retire(32'h0000007c, 32'h00000080, 5'd21, 32'h00000075);
                    28: expect_retire(32'h00000080, 32'h00000084, 5'd22, 32'h0000008d);
                    29: expect_retire(32'h00000084, 32'h0000008c, 5'd23, 32'h00000088);
                    30: expect_retire(32'h0000008c, 32'h00000090, 5'd24, 32'h0000008a);
                    31: expect_retire(32'h00000090, 32'h00000094, 5'd25, 32'h0000001d);
                    32: expect_retire(32'h00000094, 32'h000000a0, 5'd0,  32'h00000000);
                    33: expect_retire(32'h000000a0, 32'h000000a4, 5'd27, 32'h000000ac);
                    34: expect_retire(32'h000000a4, 32'h000000a8, 5'd28, 32'h00000000);
                    35: expect_retire(32'h000000a8, 32'h000000ac, 5'd0,  32'h00000000);
                    36: expect_retire(32'h000000ac, 32'h000000b0, 5'd29, 32'h00000037);
                    37: expect_retire(32'h000000b0, 32'h000000b4, 5'd0,  32'h00000000);
                    38: expect_retire(32'h000000b4, 32'h000000b8, 5'd30, 32'h000000ac);
                    39: expect_retire(32'h000000b8, 32'h000000bc, 5'd31, 32'h0000001d);
                    40: expect_retire(32'h000000bc, 32'h000000c8, 5'd0,  32'h00000000);
                    41: expect_retire(32'h000000c8, 32'h000000cc, 5'd3,  32'h0000004d);
                    42: expect_retire(32'h000000cc, 32'h000000d0, 5'd4,  32'h00000064);
                    43: expect_retire(32'h000000d0, 32'h000000d4, 5'd0,  32'h00000000);
                    44: expect_retire(32'h000000d4, 32'h000000d8, 5'd0,  32'h00000000);
                    45: expect_retire(32'h000000d8, 32'h000000dc, 5'd7,  32'h00000065);
                    46: expect_retire(32'h000000dc, 32'h000000e0, 5'd0,  32'h00000000);
                    47: expect_retire(32'h000000e0, 32'h000000e4, 5'd8,  32'h00000065);
                    default: $fatal(1, "Unexpected retirement %0d", retire_count);
                endcase

                case (rvfi.pc_rdata)
                    32'h34: expect_word_mem(1, 32'h80, 32'd29);
                    32'h38: expect_word_mem(0, 32'h80, 32'd29);
                    32'h40: expect_word_mem(0, 32'h80, 32'd29);
                    32'h48: expect_word_mem(0, 32'h80, 32'd29);
                    32'h4c: expect_word_mem(1, 32'h84, 32'd29);
                    32'h50: expect_word_mem(0, 32'h84, 32'd29);
                    32'h90: expect_word_mem(0, 32'h80, 32'd29);
                    32'hb0: expect_word_mem(1, 32'h98, 32'd172);
                    32'hb4: expect_word_mem(0, 32'h98, 32'd172);
                    32'hdc: expect_word_mem(1, 32'h9c, 32'd101);
                    32'he0: expect_word_mem(0, 32'h9c, 32'd101);
                    default: begin
                        if (rvfi.mem_rmask !== '0 || rvfi.mem_wmask !== '0)
                            $fatal(1, "Unexpected memory access at PC=%08h",
                                   rvfi.pc_rdata);
                    end
                endcase

                $display("[PASS] retire=%0d pc=%08h -> %08h rd=x%0d data=%08h",
                         retire_count, rvfi.pc_rdata, rvfi.pc_wdata,
                         rvfi.rd_addr, rvfi.rd_wdata);
                retire_count++;

                if (retire_count == NUM_TEST_INSTRS)
                    break;
            end
        end

        if (retire_count != NUM_TEST_INSTRS)
            $fatal(1, "Hazard regression timeout after %0d cycles", MAX_CYCLES);

        // Four immediate load-use dependencies, five taken redirects.
        if (stall_cycles != 4 || redirect_count != 5)
            $fatal(1, "Pipeline control count mismatch: stalls=%0d redirects=%0d",
                   stall_cycles, redirect_count);

        if (!saw_priority || ex_a_count == 0 || ex_b_count == 0 ||
            wb_a_count == 0 || wb_b_count == 0)
            $fatal(1,
                "Forwarding coverage missing: priority=%0b EX_A=%0d EX_B=%0d WB_A=%0d WB_B=%0d",
                saw_priority, ex_a_count, ex_b_count, wb_a_count, wb_b_count);

        // Check both legitimate stores and sentinel-protected wrong paths.
        if (u_dut.u_mem_stage.u_data_mem.mem[32] !== 32'd29  ||
            u_dut.u_mem_stage.u_data_mem.mem[33] !== 32'd29  ||
            u_dut.u_mem_stage.u_data_mem.mem[34] !== 32'hA5A5A5A5 ||
            u_dut.u_mem_stage.u_data_mem.mem[35] !== 32'hB6B6B6B6 ||
            u_dut.u_mem_stage.u_data_mem.mem[36] !== 32'hC7C7C7C7 ||
            u_dut.u_mem_stage.u_data_mem.mem[37] !== 32'hD8D8D8D8 ||
            u_dut.u_mem_stage.u_data_mem.mem[38] !== 32'd172 ||
            u_dut.u_mem_stage.u_data_mem.mem[39] !== 32'd101)
            $fatal(1, "Wrong-path store or final memory state mismatch");

        if (u_dut.u_id_stage.u_reg_file.x[1] !== 32'h80)
            $fatal(1, "Wrong-path instruction modified x1");

        $display("HAZARD REGRESSION PASSED: %0d instructions, %0d stalls, %0d redirects",
                 retire_count, stall_cycles, redirect_count);
        $finish;
    end
endmodule

