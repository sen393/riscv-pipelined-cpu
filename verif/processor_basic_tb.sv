
module processor_basic_tb;
    import riscv_pkg::*;

    timeunit 1ns;
    timeprecision 1ps;

    // --------------------------------------------------------
    // Test parameters
    // --------------------------------------------------------

    localparam int unsigned CLK_PERIOD = 10;
    localparam int unsigned MAX_CYCLES = 60;
    localparam int unsigned NUM_TEST_INSTRS = 2;

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
        .IMEM_INIT_FILE("../verif/programs/ebreak.hex")
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
    // Retirement monitor
    // --------------------------------------------------------

    initial begin

        wait (rst == 1'b0);

        repeat (MAX_CYCLES) begin
            @(negedge clk);

            if (rvfi.valid) begin

                $display(
                    "[RETIRE] order=%0d pc=%08h instr=%08h rd=x%0d data=%08h next_pc=%08h",
                    rvfi.order,
                    rvfi.pc_rdata,
                    rvfi.insn,
                    rvfi.rd_addr,
                    rvfi.rd_wdata,
                    rvfi.pc_wdata
                );

                // Print memory accesses
                if (rvfi.mem_rmask != '0 ||
                    rvfi.mem_wmask != '0) begin

                    $display(
                        "         mem_addr=%08h rmask=%b rdata=%08h wmask=%b wdata=%08h",
                        rvfi.mem_addr,
                        rvfi.mem_rmask,
                        rvfi.mem_rdata,
                        rvfi.mem_wmask,
                        rvfi.mem_wdata
                    );

                end

                retire_count++;

               if (retire_count == NUM_TEST_INSTRS) begin

                    // Verify EBREAK instruction and trap
                    if (rvfi.insn !== 32'h00100073 || rvfi.trap !== 1'b1)
                        $fatal(1, "Expected EBREAK trap");

                    // Verify exception PC
                    if (rvfi.pc_rdata !== 32'h00000004)
                        $fatal(1, "Exception occurred at incorrect PC");

                    $display("[TRAP] EBREAK at PC=%08h", rvfi.pc_rdata);

                    // Verify no younger instructions retire
                    repeat (8) begin
                        @(negedge clk);

                        if (rvfi.valid)
                            $fatal(1, "Unexpected retirement after EBREAK");
                    end

                    $display("EBREAK TEST PASSED");
                    $finish;

                end 
            end
        end

        $fatal(1, "Simulation timeout");

    end

endmodule
