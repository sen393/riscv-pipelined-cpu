
module processor_bram_tb;
    import riscv_pkg::*;

    localparam int unsigned MAX_CYCLES = 300;
    localparam int unsigned NUM_INSTR  = 27;
    localparam int unsigned EXPECTED_RETIRE = 19;

    // --------------------------------------------------------
    // Test program
    // --------------------------------------------------------

    localparam logic [31:0] PROGRAM [0:NUM_INSTR-1] = '{
        // Original memory tests
        32'h02A00093,   // 0x00: addi x1, x0, 42
        32'h00102023,   // 0x04: sw   x1, 0(x0)
        32'h00002103,   // 0x08: lw   x2, 0(x0)
        32'h002081B3,   // 0x0C: add  x3, x1, x2

        32'hFFF00213,   // 0x10: addi x4, x0, -1
        32'h004000A3,   // 0x14: sb   x4, 1(x0)
        32'h00104283,   // 0x18: lbu  x5, 1(x0)
        32'h00100303,   // 0x1C: lb   x6, 1(x0)

        32'h00401123,   // 0x20: sh   x4, 2(x0)
        32'h00205383,   // 0x24: lhu  x7, 2(x0)
        32'h00201403,   // 0x28: lh   x8, 2(x0)
        32'h00002483,   // 0x2C: lw   x9, 0(x0)

        // Control-flow instructions start here
        32'h00100513,   // 0x30: addi x10, x0, 1

        32'h00A50663,   // 0x34: beq  x10, x10, +12

        32'h00A02423,   // 0x38: sw   x10, 8(x0) WRONG PATH
        32'h06300593,   // 0x3C: addi x11, x0, 99 WRONG PATH

        32'h00C002EF,   // 0x40: jal  x5, +12

        32'h00A02423,   // 0x44: sw   x10, 8(x0) WRONG PATH
        32'h06300613,   // 0x48: addi x12, x0, 99 WRONG PATH

        32'h06000313,   // 0x4C: addi x6, x0, 0x60
        32'h000303E7,   // 0x50: jalr x7, 0(x6)

        32'h00A02423,   // 0x54: sw   x10, 8(x0) WRONG PATH
        32'h06300693,   // 0x58: addi x13, x0, 99 WRONG PATH
        32'h06300713,   // 0x5C: addi x14, x0, 99 WRONG PATH

        32'h00700793,   // 0x60: addi x15, x0, 7
        32'h00100F93,   // 0x64: addi x31, x0, 1
        32'h00100073    // 0x68: ebreak
    };

    localparam logic [31:0] EXPECTED_PC
        [0:EXPECTED_RETIRE-1] = '{

        // Original memory tests
        32'h00, 32'h04, 32'h08, 32'h0C,
        32'h10, 32'h14, 32'h18, 32'h1C,
        32'h20, 32'h24, 32'h28, 32'h2C,

        // Control-flow tests
        32'h30,  // ADDI x10
        32'h34,  // BEQ
        32'h40,  // JAL
        32'h4C,  // ADDI x6
        32'h50,  // JALR
        32'h60,  // ADDI x15
        32'h64   // Completion marker
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
        .DMEM_DEPTH_WORDS (256),
        .IMEM_INIT_FILE   ("../verif/programs/bram_system.hex")
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
        // Instruction BRAM initialized through $readmemh
        #1;

        // Sentinel to detect wrong-path stores
        dut.u_dmem.u_bram.mem[2] = 32'hCAFE_BABE;

        $display("[TB] Instruction BRAM loaded from HEX file");

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

                if (dut.dmem_bus.req_write) begin

                    case (write_requests)

                        // SW: all four bytes
                        0: if (dut.dmem_bus.req_wstrb !== 4'b1111)
                            $fatal(1, "[FAIL] SW strobe");

                        // SB: byte lane 1
                        1: if (dut.dmem_bus.req_wstrb !== 4'b0010)
                            $fatal(1, "[FAIL] SB strobe");

                        // SH: byte lanes 2 and 3
                        2: if (dut.dmem_bus.req_wstrb !== 4'b1100)
                            $fatal(1, "[FAIL] SH strobe");

                        default:
                            $fatal(1, "[FAIL] Extra write request");

                    endcase

                    write_requests++;

                end
                else begin
                    read_requests++;
                end

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


                // --------------------------------------------------------
                // Instruction and PC correctness
                // --------------------------------------------------------

                // Verify expected retirement PC
                if (rvfi.pc_rdata !== EXPECTED_PC[retired])
                    $fatal(1,
                        "[FAIL] PC mismatch: got=%h expected=%h",
                        rvfi.pc_rdata, EXPECTED_PC[retired]);

                // Verify instruction at the expected PC
                if (rvfi.insn !== PROGRAM[EXPECTED_PC[retired] >> 2])
                    $fatal(1,
                        "[FAIL] Instruction mismatch at order %0d: got=%h expected=%h",
                        retired,
                        rvfi.insn,
                        PROGRAM[EXPECTED_PC[retired] >> 2]);

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
                        if (rvfi.rd_addr !== 5'd4 ||
                            rvfi.rd_wdata !== 32'hFFFF_FFFF)
                            $fatal(1, "[FAIL] ADDI x4");
                    end

                    6: begin
                        if (rvfi.rd_addr !== 5'd5 ||
                            rvfi.rd_wdata !== 32'h0000_00FF)
                            $fatal(1, "[FAIL] LBU x5");
                    end

                    7: begin
                        if (rvfi.rd_addr !== 5'd6 ||
                            rvfi.rd_wdata !== 32'hFFFF_FFFF)
                            $fatal(1, "[FAIL] LB x6");
                    end

                    9: begin
                        if (rvfi.rd_addr !== 5'd7 ||
                            rvfi.rd_wdata !== 32'h0000_FFFF)
                            $fatal(1, "[FAIL] LHU x7");
                    end

                    10: begin
                        if (rvfi.rd_addr !== 5'd8 ||
                            rvfi.rd_wdata !== 32'hFFFF_FFFF)
                            $fatal(1, "[FAIL] LH x8");
                    end

                    11: begin
                        if (rvfi.rd_addr !== 5'd9 ||
                            rvfi.rd_wdata !== 32'hFFFF_FF2A)
                            $fatal(1, "[FAIL] LW x9");
                    end


                    // --------------------------------------------------------
                    // Control flow tests
                    // --------------------------------------------------------

                    // ADDI x10
                    12: begin
                        if (rvfi.rd_addr !== 5'd10 ||
                            rvfi.rd_wdata !== 32'd1)
                            $fatal(1, "[FAIL] ADDI x10");
                    end

                    // BEQ: PC already checked by EXPECTED_PC
                    13: ;

                    // JAL x5: return address = 0x44
                    14: begin
                        if (rvfi.rd_addr !== 5'd5 ||
                            rvfi.rd_wdata !== 32'h44)
                            $fatal(1, "[FAIL] JAL link address");
                    end

                    // ADDI x6: target for JALR
                    15: begin
                        if (rvfi.rd_addr !== 5'd6 ||
                            rvfi.rd_wdata !== 32'h60)
                            $fatal(1, "[FAIL] JALR target setup");
                    end

                    // JALR x7: return address = 0x54
                    16: begin
                        if (rvfi.rd_addr !== 5'd7 ||
                            rvfi.rd_wdata !== 32'h54)
                            $fatal(1, "[FAIL] JALR link address");
                    end

                    // ADDI x15: successful redirect
                    17: begin
                        if (rvfi.rd_addr !== 5'd15 ||
                            rvfi.rd_wdata !== 32'd7)
                            $fatal(1, "[FAIL] JALR target execution");
                    end

                    // Completion marker
                    18: begin
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
                    if (dut.u_dmem.u_bram.mem[0] !== 32'hFFFF_FF2A)
                        $fatal(1,
                            "[FAIL] Data BRAM[0] mismatch");

                    // Ensure wrong-path stores were suppressed
                    if (dut.u_dmem.u_bram.mem[2] !== 32'hCAFE_BABE)
                        $fatal(1, "[FAIL] Wrong-path store corrupted memory");

                    // Verify exactly one read and one write
                    if (read_requests != 6 ||
                        write_requests != 3)
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
