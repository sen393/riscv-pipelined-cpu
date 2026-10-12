module processor_memory_tb;
    import riscv_pkg::*;

    timeunit 1ns;
    timeprecision 1ps;


    // --------------------------------------------------------
    // Test parameters
    // --------------------------------------------------------

    localparam int unsigned CLK_PERIOD = 10;
    localparam int unsigned MAX_CYCLES = 160;
    localparam int unsigned NUM_TEST_INSTRS = 26;

    // --------------------------------------------------------
    // DUT signals
    // --------------------------------------------------------

    logic       clk;
    logic       rst;
    retire_t    rvfi;

    int unsigned retire_count = 0;

    // --------------------------------------------------------
    // Instantiate DUT
    // --------------------------------------------------------

    riscv_core #(
        .IMEM_INIT_FILE("../verif/programs/memory.hex")
    ) u_dut (
        .clk    (clk),
        .rst    (rst),
        .rvfi   (rvfi)
    );

    // --------------------------------------------------------
    // Clock generation
    // --------------------------------------------------------

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // --------------------------------------------------------
    // Reset sequence
    // --------------------------------------------------------

    initial begin
        rst = 1'b1;

        repeat (3) @(negedge clk);

        rst = 1'b0;
    end


    // --------------------------------------------------------
    // Define tasks
    // --------------------------------------------------------

    task automatic expect_rd(
        input   addr_t      expected_rd,
        input   word_t      expected_data
    );
         if ((rvfi.rd_addr !== expected_rd) || (rvfi.rd_wdata !== expected_data)) begin
            $fatal(1,
                "[RETIRE %0d] Register mismatch: got x%0d=%08h, expected x%0d=%08h",
                retire_count, rvfi.rd_addr, rvfi.rd_wdata,
                expected_rd, expected_data);
        end
    endtask    

    task automatic expect_load(
        input   addr_t      expected_rd,
        input   word_t      expected_data,
        input   addr_t      expected_addr,
        input   byte_mask_t expected_mask,
        input   word_t      expected_raw_word
    );
        expect_rd(expected_rd, expected_data);
        if (rvfi.mem_addr   !== expected_addr   ||
            rvfi.mem_rmask  !== expected_mask   ||
            rvfi.mem_wmask  !== 4'b0000         ||
            rvfi.mem_rdata  !== expected_raw_word) begin
            $fatal(1,
                "[RETIRE %0d] Load metadata mismatch: addr=%08h, rmask=%0b, rdata=%08h, wmask=%0b",
                retire_count, rvfi.mem_addr, rvfi.mem_rmask, rvfi.mem_rdata, rvfi.mem_wmask);
        end
    endtask

    task automatic expect_store(
        input   addr_t      expected_addr,
        input   byte_mask_t expected_mask,
        input   word_t      expected_data
    );
        word_t active_mask;

        // Expand each byte-enable bit into 8 bits
        active_mask = '0;
        for (int i = 0; i < NUM_BYTES; i++) begin
            active_mask[8*i +: 8] = {8{expected_mask[i]}};
        end

        if (rvfi.rd_addr !== '0                 ||
            rvfi.mem_addr   !== expected_addr   ||
          ((rvfi.mem_wdata & active_mask) !==
           (expected_data & active_mask))       ||
            rvfi.mem_rmask  !== 4'b0000         ||
            rvfi.mem_wmask  !== expected_mask) begin
                $fatal(1,
                    "[RETIRE %0d] Store metadata mismatch: addr=%08h, wmask=%0b, rmask=%0b, wdata=%08h",
                    retire_count, rvfi.mem_addr, rvfi.mem_wmask, rvfi.mem_rmask, rvfi.mem_wdata);
        end
    endtask

    initial begin
        wait (rst == 1'b0);

        repeat (MAX_CYCLES) begin
            // Sample after the DUT's posedge nonblocking assignments settle.
            @(negedge clk);

            if (rvfi.valid) begin
                if (rvfi.order !== retire_count)
                    $fatal(1, "Retirement order mismatch at %0d", retire_count);

                if (rvfi.pc_rdata !== (retire_count * 4) ||
                    rvfi.pc_wdata !== ((retire_count + 1) * 4))
                    $fatal(1, "Unexpected PC transition at %0d: %08h -> %08h",
                        retire_count, rvfi.pc_rdata, rvfi.pc_wdata);

                if (rvfi.trap || rvfi.halt)
                    $fatal(1, "Unexpected trap/halt at PC %08h", rvfi.pc_rdata);

                // Check all register-writing instructions and every store.
                // Indices correspond to lines in verif/programs/memory.hex.
                case (retire_count)
                     0: expect_rd   ( 1, 32'h00000080);  // base pointer
                     1: expect_rd   ( 2, 32'h12345000);  // LUI
                     2: expect_rd   ( 2, 32'h12345678);  // ADDI
                     3: expect_store(32'h80, 4'b1111, 32'h12345678);
                     4: expect_load ( 3, 32'h12345678, 32'h80, 4'b1111, 32'h12345678);
                     5: expect_load ( 4, 32'h00000012, 32'h80, 4'b1000, 32'h12345678);
                     6: expect_load ( 5, 32'h00000034, 32'h80, 4'b0100, 32'h12345678);
                     7: expect_load ( 6, 32'h00001234, 32'h80, 4'b1100, 32'h12345678);
                     8: expect_load ( 7, 32'h00005678, 32'h80, 4'b0011, 32'h12345678);
                     9: expect_rd   ( 8, 32'hFFFFFFFF);  // -1
                    10: expect_store(32'h80, 4'b0010, 32'h0000FF00);
                    11: expect_load ( 9, 32'h1234FF78, 32'h80, 4'b1111, 32'h1234FF78);
                    12: expect_load (10, 32'hFFFFFFFF, 32'h80, 4'b0010, 32'h1234FF78);
                    13: expect_load (11, 32'h000000FF, 32'h80, 4'b0010, 32'h1234FF78);
                    14: expect_store(32'h80, 4'b1100, 32'hFFFF0000);
                    15: expect_load (12, 32'hFFFFFF78, 32'h80, 4'b1111, 32'hFFFFFF78);
                    16: expect_load (13, 32'hFFFFFFFF, 32'h80, 4'b1100, 32'hFFFFFF78);
                    17: expect_load (14, 32'h0000FFFF, 32'h80, 4'b1100, 32'hFFFFFF78);
                    18: expect_store(32'h84, 4'b1111, 32'h12345678);
                    19: expect_store(32'h84, 4'b0001, 32'h000000FF);
                    20: expect_load (15, 32'h123456FF, 32'h84, 4'b1111, 32'h123456FF);
                    21: expect_load (16, 32'hFFFFFF78, 32'h80, 4'b1111, 32'hFFFFFF78);
                    22: expect_rd   (17, 32'hFFFFFF79);  // load-use hazard
                    23: expect_rd   (18, 32'hFFFFFF7A);  // EX forwarding
                    24: expect_store(32'h88, 4'b1111, 32'hFFFFFF79);
                    25: expect_load (19, 32'hFFFFFF79, 32'h88, 4'b1111, 32'hFFFFFF79);
                    default:
                        $fatal(1, "Unexpected extra retirement %0d", retire_count);
                endcase

                $display("[PASS] retire=%0d pc=%08h insn=%08h",
                    retire_count, rvfi.pc_rdata, rvfi.insn);
                retire_count++;

                if (retire_count == NUM_TEST_INSTRS) begin
                    // White-box check: ensures the final physical memory state
                    // agrees with the retirement-level checks above.
                    if (u_dut.u_mem_stage.u_data_mem.mem[32] !== 32'hFFFFFF78 ||
                        u_dut.u_mem_stage.u_data_mem.mem[33] !== 32'h123456FF ||
                        u_dut.u_mem_stage.u_data_mem.mem[34] !== 32'hFFFFFF79)
                        $fatal(1, "Final data-memory contents incorrect");

                    $display("MEMORY REGRESSION PASSED: %0d instructions", retire_count);

                    break;
                end
            end
        end

        if (retire_count !== NUM_TEST_INSTRS)
            $fatal(1, "Memory regression timeout after %0d cycles", MAX_CYCLES);

        $finish;
    end

endmodule

