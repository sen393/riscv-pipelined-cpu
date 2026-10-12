module processor_system_tb;
    import riscv_pkg::*;

    timeunit 1ns;
    timeprecision 1ps;

    localparam int unsigned CLK_PERIOD = 10;
    localparam int unsigned MAX_CYCLES = 100;
    localparam int unsigned POST_TRAP_CYCLES = 12;
    localparam word_t BASE_ADDR = 32'h0000_0080;
    localparam word_t SENTINEL  = 32'hDEAD_BEEF;

    logic clk = 1'b0;
    logic rst;
    retire_t rvfi;

    string test_case;
    string program_file;
    instr_t expected_fault_insn;
    exc_kind_e expected_exc;
    int unsigned retire_count;
    int unsigned expected_retires;
    bit saw_trap;
    bit fence_case;

    riscv_core #(
        .IMEM_INIT_FILE("")  // testbench loads/patches the ROM before reset is released
    ) u_dut (
        .clk(clk),
        .rst(rst),
        .rvfi(rvfi)
    );

    always #(CLK_PERIOD / 2) clk = ~clk;

    // Configure the instruction inserted at PC 0x10 in system_fault.hex.
    // All exception cases have the same preceding and following instructions.
    task automatic select_case();
        fence_case = (test_case == "fence");
        expected_fault_insn = '0;
        expected_exc = EXC_NONE;
        expected_retires = fence_case ? 10 : 5;
        program_file = fence_case
            ? "../verif/programs/system_fence.hex"
            : "../verif/programs/system_fault.hex";

        case (test_case)
            "fence":              begin expected_exc = EXC_ECALL;                                                  end
            "ecall":              begin expected_fault_insn = 32'h0000_0073; expected_exc = EXC_ECALL;             end
            "ebreak":             begin expected_fault_insn = 32'h0010_0073; expected_exc = EXC_EBREAK;            end
            "illegal":            begin expected_fault_insn = 32'h0000_0000; expected_exc = EXC_ILLEGAL;           end
            "illegal_system":     begin expected_fault_insn = 32'h3020_0073; expected_exc = EXC_ILLEGAL;           end
            "illegal_load":       begin expected_fault_insn = 32'h0000_b303; expected_exc = EXC_ILLEGAL;           end
            "illegal_fence_i":    begin expected_fault_insn = 32'h0000_100f; expected_exc = EXC_ILLEGAL;           end
            "lw_misaligned":      begin expected_fault_insn = 32'h0020_a303; expected_exc = EXC_LOAD_MISALIGNED;   end
            "lh_misaligned":      begin expected_fault_insn = 32'h0010_9303; expected_exc = EXC_LOAD_MISALIGNED;   end
            "sw_misaligned":      begin expected_fault_insn = 32'h0020_a123; expected_exc = EXC_STORE_MISALIGNED;  end
            "sh_misaligned":      begin expected_fault_insn = 32'h0020_90a3; expected_exc = EXC_STORE_MISALIGNED;  end
            "jal_misaligned":     begin expected_fault_insn = 32'h0020_036f; expected_exc = EXC_INSTR_MISALIGNED;  end
            "jalr_misaligned":    begin expected_fault_insn = 32'h0020_8367; expected_exc = EXC_INSTR_MISALIGNED;  end
            "branch_misaligned":  begin expected_fault_insn = 32'h0021_0163; expected_exc = EXC_INSTR_MISALIGNED;  end
            default: $fatal(1, "Unknown +CASE=%s", test_case);
        endcase
    endtask

    task automatic check_register(
        input reg_addr_t rd,
        input word_t value
    );
        if (rvfi.rd_addr !== rd || rvfi.rd_wdata !== value)
            $fatal(1, "[%s] retire=%0d: got x%0d=%08h; expected x%0d=%08h",
                test_case, retire_count, rvfi.rd_addr, rvfi.rd_wdata, rd, value);
        if (rvfi.mem_rmask !== '0 || rvfi.mem_wmask !== '0)
            $fatal(1, "[%s] register instruction unexpectedly accessed memory", test_case);
    endtask

    task automatic check_no_side_effects();
        if (rvfi.rd_addr !== '0 || rvfi.rd_wdata !== '0 ||
            rvfi.mem_rmask !== '0 || rvfi.mem_wmask !== '0)
            $fatal(1, "[%s] retire=%0d: unwanted architectural side effect",
                test_case, retire_count);
    endtask

    task automatic check_store();
        if (rvfi.rd_addr !== '0 || rvfi.rd_wdata !== '0 ||
            rvfi.mem_addr !== BASE_ADDR ||
            rvfi.mem_rmask !== '0 || rvfi.mem_wmask !== 4'b1111 ||
            rvfi.mem_wdata !== 32'd42)
            $fatal(1, "[%s] initial store metadata wrong: addr=%08h mask=%b data=%08h",
                test_case, rvfi.mem_addr, rvfi.mem_wmask, rvfi.mem_wdata);
    endtask

    task automatic check_retirement();
        if (rvfi.order !== retire_count)
            $fatal(1, "[%s] wrong retirement order: got=%0d expected=%0d",
                test_case, rvfi.order, retire_count);

        // Each program's expected architectural retirements are sequential.
        // A misaligned control-flow target must trap rather than redirect.
        if (rvfi.pc_rdata !== (retire_count * 4))
            $fatal(1, "[%s] unexpected retired PC=%08h at index=%0d",
                test_case, rvfi.pc_rdata, retire_count);

        if (rvfi.insn !== u_dut.u_if_stage.u_instr_mem.mem[retire_count])
            $fatal(1, "[%s] wrong retired instruction at PC=%08h", test_case, rvfi.pc_rdata);

        if (rvfi.intr !== 1'b0)
            $fatal(1, "[%s] unexpected interrupt", test_case);

        if (retire_count == expected_retires - 1) begin
            if (rvfi.trap !== 1'b1 || rvfi.halt !== 1'b1 ||
                u_dut.mem_wb_q.ctrl.exc_kind !== expected_exc)
                $fatal(1, "[%s] wrong trap/halt/cause at PC=%08h (cause=%0d, expected=%0d)",
                    test_case, rvfi.pc_rdata, u_dut.mem_wb_q.ctrl.exc_kind, expected_exc);
            check_no_side_effects();
            saw_trap = 1'b1;
        end else begin
            if (rvfi.trap !== 1'b0 || rvfi.halt !== 1'b0)
                $fatal(1, "[%s] premature trap at PC=%08h", test_case, rvfi.pc_rdata);

            case (retire_count)
                0: check_register(5'd1, BASE_ADDR);
                1: check_register(5'd2, 32'd42);
                2: check_register(5'd6, 32'd7);
                3: check_store();
                4, 5, 6: begin
                    if (!fence_case)
                        $fatal(1, "[%s] unexpected extra instruction", test_case);
                    check_no_side_effects(); // not-taken BNE and two FENCE instructions
                    if (rvfi.pc_wdata !== rvfi.pc_rdata + 32'd4)
                        $fatal(1, "[%s] BNE/FENCE unexpectedly redirected", test_case);
                end
                7: begin
                    if (!fence_case) $fatal(1, "Unexpected load");
                    if (rvfi.rd_addr !== 5'd3 || rvfi.rd_wdata !== 32'd42)
                        $fatal(1, "[%s] FENCE-following load register result wrong", test_case);
                    if (rvfi.mem_addr !== BASE_ADDR ||
                        rvfi.mem_rmask !== 4'b1111 ||
                        rvfi.mem_wmask !== '0 ||
                        rvfi.mem_rdata !== 32'd42)
                        $fatal(1, "[%s] FENCE-following load metadata wrong", test_case);
                end
                8: check_register(5'd4, 32'd43);
                default: $fatal(1, "[%s] unexpected retirement index %0d", test_case, retire_count);
            endcase
        end

        $display("[%s] [PASS] retire=%0d pc=%08h insn=%08h trap=%b",
            test_case, retire_count, rvfi.pc_rdata, rvfi.insn, rvfi.trap);
        retire_count++;
    endtask

    initial begin
        rst = 1'b1;
        retire_count = 0;
        saw_trap = 0;

        if (!$value$plusargs("CASE=%s", test_case))
            $fatal(1, "Supply +CASE=<name> (e.g. +CASE=ecall)");
        select_case();

        // Each simulation process runs a single test with a fresh DUT state.
        // Only addresses 0x80 and 0x84 are inspected after the trap.
        $readmemh(program_file, u_dut.u_if_stage.u_instr_mem.mem);
        if (!fence_case)
            u_dut.u_if_stage.u_instr_mem.mem[4] = expected_fault_insn;

        u_dut.u_mem_stage.u_data_mem.mem[32] = 32'hA5A5_A5A5;
        u_dut.u_mem_stage.u_data_mem.mem[33] = SENTINEL;

        repeat (3) @(negedge clk);
        rst = 1'b0;

        repeat (MAX_CYCLES) begin
            @(negedge clk);
            if (rvfi.valid) begin
                check_retirement();
                if (saw_trap) break;
            end
        end

        if (!saw_trap || retire_count != expected_retires)
            $fatal(1, "[%s] missing trap/retirement; completed %0d/%0d",
                test_case, retire_count, expected_retires);

        // Verify exception precision *after* the fault has retired:
        // older store committed, faulting instruction did not write,
        // and all younger register/memory operations were killed.
        repeat (POST_TRAP_CYCLES) begin
            @(negedge clk);
            if (rvfi.valid || u_dut.wb_reg_write || u_dut.u_mem_stage.mem_write_en)
                $fatal(1, "[%s] post-trap retirement/write detected", test_case);

            if (u_dut.u_mem_stage.u_data_mem.mem[32] !== 32'd42 ||
                u_dut.u_mem_stage.u_data_mem.mem[33] !== SENTINEL)
                $fatal(1, "[%s] old store lost or wrong-path store modified memory", test_case);

            if (u_dut.u_id_stage.u_reg_file.x[6] !== 32'd7)
                $fatal(1, "[%s] faulting/younger instruction modified x6", test_case);
        end

        if (fence_case &&
            (u_dut.u_id_stage.u_reg_file.x[3] !== 32'd42 ||
             u_dut.u_id_stage.u_reg_file.x[4] !== 32'd43))
            $fatal(1, "[%s] FENCE sequencing/register state incorrect", test_case);

        $display("SYSTEM CASE PASSED: %s (%0d retired; trap cause %0d; no younger commits)",
            test_case, retire_count, expected_exc);
        $finish;
    end
endmodule

