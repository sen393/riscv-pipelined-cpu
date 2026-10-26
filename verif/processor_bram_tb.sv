
module processor_bram_tb;
    import riscv_pkg::*;

    localparam int unsigned MAX_CYCLES = 300;
    localparam int unsigned NUM_INSTR  = 6;
    localparam int unsigned EXPECTED_RETIRE = 5;

    // --------------------------------------------------------
    // Test program
    // --------------------------------------------------------

    localparam logic [31:0] PROGRAM [0:NUM_INSTR-1] = '{
        32'h02A00093,   // addi x1, x0, 42
        32'h00102023,   // sw   x1, 0(x0)
        32'h00002103,   // lw   x2, 0(x0)
        32'h002081B3,   // add  x3, x1, x2
        32'h00100F93,   // addi x31, x0, 1
        32'h00100073    // ebreak
    };

    // --------------------------------------------------------
    // Testbench signals
    // --------------------------------------------------------

    logic clk = 1'b0;
    logic rst = 1'b1;

    retire_t rvfi;

    logic fetch_error;
    logic data_access_fault;

    int unsigned cycles = 0;
    int unsigned retired = 0;

    int unsigned read_requests = 0;
    int unsigned write_requests = 0;

    // --------------------------------------------------------
    // Clock generation
    // --------------------------------------------------------

    always #5 clk = ~clk;

    // --------------------------------------------------------
    // DUT
    // --------------------------------------------------------

    riscv_system #(
        .IMEM_DEPTH_WORDS (256),
        .DMEM_DEPTH_WORDS (256)
    ) dut (
        .clk               (clk),
        .rst               (rst),

        .rvfi              (rvfi),

        .fetch_error       (fetch_error),
        .data_access_fault (data_access_fault)
    );

    // --------------------------------------------------------
    // Initialization and reset
    // --------------------------------------------------------

    initial begin
        // Initialize instruction BRAM before reset release
        #1;
        for (int i = 0; i < NUM_INSTR; i++) begin
            dut.u_imem.u_bram.mem[i] = PROGRAM[i];
        end

        $display("[TB] Instruction BRAM initialized");

        repeat (5) @(negedge clk);
        rst = 1'b0;

        $display("[TB] Reset released");
    end

    // --------------------------------------------------------
    // Data bus transaction monitoring
    // --------------------------------------------------------

    always @(posedge clk) begin
        if (!rst) begin
            if (dut.dmem_bus.req_valid &&
                dut.dmem_bus.req_ready) begin

                if (dut.dmem_bus.req_write)
                    write_requests++;
                else
                    read_requests++;

            end
        end
    end

    // --------------------------------------------------------
    // Retirement monitoring and checking
    // --------------------------------------------------------

    always @(negedge clk) begin
        if (!rst) begin
            cycles++;

            // Detect unexpected memory faults
            if (fetch_error || data_access_fault) begin
                $fatal(1,
                    "[FAIL] Memory fault: fetch=%b data=%b",
                    fetch_error, data_access_fault);
            end

            if (rvfi.valid) begin

                // No unexpected extra retirements
                if (retired >= EXPECTED_RETIRE)
                    $fatal(1, "[FAIL] Extra retirement");

                // Retirement ordering
                if (rvfi.order !== retired)
                    $fatal(1,
                        "[FAIL] Retirement order: got=%0d expected=%0d",
                        rvfi.order, retired);

                // Instruction and PC correctness
                if (rvfi.insn !== PROGRAM[retired])
                    $fatal(1,
                        "[FAIL] Instruction mismatch at order %0d",
                        retired);

                if (rvfi.pc_rdata !== (retired * 4))
                    $fatal(1,
                        "[FAIL] PC mismatch: got=%h expected=%h",
                        rvfi.pc_rdata, retired * 4);

                // No traps for expected instructions
                if (rvfi.trap)
                    $fatal(1,
                        "[FAIL] Unexpected trap at PC=%h",
                        rvfi.pc_rdata);

                // Check register writeback results
                case (retired)

                    0: begin
                        if (rvfi.rd_addr !== 5'd1 ||
                            rvfi.rd_wdata !== 32'd42)
                            $fatal(1, "[FAIL] ADDI x1");
                    end

                    2: begin
                        if (rvfi.rd_addr !== 5'd2 ||
                            rvfi.rd_wdata !== 32'd42)
                            $fatal(1, "[FAIL] LW x2");
                    end

                    3: begin
                        if (rvfi.rd_addr !== 5'd3 ||
                            rvfi.rd_wdata !== 32'd84)
                            $fatal(1, "[FAIL] ADD x3");
                    end

                    4: begin
                        if (rvfi.rd_addr !== 5'd31 ||
                            rvfi.rd_wdata !== 32'd1)
                            $fatal(1, "[FAIL] Completion marker");
                    end

                    default: ;

                endcase

                $display(
                    "[RETIRE] order=%0d pc=%h insn=%h rd=x%0d data=%h",
                    rvfi.order,
                    rvfi.pc_rdata,
                    rvfi.insn,
                    rvfi.rd_addr,
                    rvfi.rd_wdata
                );

                retired++;

                // --------------------------------------------
                // Final system checks
                // --------------------------------------------

                if (retired == EXPECTED_RETIRE) begin

                    // Verify physical data BRAM contents
                    if (dut.u_dmem.u_bram.mem[0] !== 32'd42)
                        $fatal(1,
                            "[FAIL] Data BRAM[0] mismatch");

                    // Verify exactly one read and one write
                    if (read_requests != 1 ||
                        write_requests != 1)
                        $fatal(1,
                            "[FAIL] Memory requests: reads=%0d writes=%0d",
                            read_requests, write_requests);

                    $display("");
                    $display("====================================");
                    $display(" BRAM SYSTEM TEST PASSED");
                    $display(" Cycles: %0d", cycles);
                    $display(" Retired: %0d", retired);
                    $display(" Memory[0]: %h",
                             dut.u_dmem.u_bram.mem[0]);
                    $display("====================================");

                    $finish;
                end

            end

            // Timeout protection
            if (cycles >= MAX_CYCLES)
                $fatal(1,
                    "[FAIL] Timeout after %0d cycles; retired=%0d",
                    cycles, retired);

        end
    end

endmodule
