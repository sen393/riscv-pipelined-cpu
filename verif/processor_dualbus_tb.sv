
module processor_dualbus_tb;
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

    mem_bus_if imem_bus (
        .clk (clk),
        .rst (rst)
    );

    mem_bus_if dmem_bus (
        .clk (clk),
        .rst (rst)
    );

    logic [7:0] imem_delay;
    logic [7:0] dmem_delay;

    assign imem_delay = 8'd0;

    // Create different delays
    assign dmem_delay =
        dmem_bus.req_addr[2] ? 8'd4 : 8'd6;

    // --------------------------------------------------------
    // Processor
    // --------------------------------------------------------

    retire_t rvfi;
    logic fetch_error;
    logic data_access_fault;

    riscv_core_ifbus dut (
        .clk                (clk),
        .rst                (rst),
        .imem               (imem_bus),
        .dmem               (dmem_bus),
        .rvfi               (rvfi),
        .fetch_error        (fetch_error),
        .data_access_fault  (data_access_fault)
    );

    // --------------------------------------------------------
    // Instruction memory
    // --------------------------------------------------------

    mem_bus_memory_model #(
        .DEPTH_WORDS (64),
        .BASE_ADDR   (32'h0000_0000)
    ) u_imem (
        .bus            (imem_bus),
        .response_delay (imem_delay)
    );

    // --------------------------------------------------------
    // Data memory
    // --------------------------------------------------------

    mem_bus_memory_model #(
        .DEPTH_WORDS (64),
        .BASE_ADDR   (32'h0000_1000)
    ) u_dmem (
        .bus            (dmem_bus),
        .response_delay (dmem_delay)
    );

    // --------------------------------------------------------
    // Program and memory initialization
    // --------------------------------------------------------

    initial begin
        @(negedge clk);

        u_imem.mem[0]  = 32'h0000_10B7; // lui  x1, 0x1
        u_imem.mem[1]  = 32'h02A0_0293; // addi x5, x0, 42
        u_imem.mem[2]  = 32'h0050_A023; // sw   x5, 0(x1)
        u_imem.mem[3]  = 32'h0000_A303; // lw   x6, 0(x1)
        u_imem.mem[4]  = 32'h0053_03B3; // add  x7, x6, x5
        u_imem.mem[5]  = 32'hFFF0_0413; // addi x8, x0, -1
        u_imem.mem[6]  = 32'h0080_80A3; // sb   x8, 1(x1)
        u_imem.mem[7]  = 32'h0010_C483; // lbu  x9, 1(x1)
        u_imem.mem[8]  = 32'h0010_8503; // lb   x10, 1(x1)
        u_imem.mem[9]  = 32'h0080_9123; // sh   x8, 2(x1)
        u_imem.mem[10] = 32'h0020_D583; // lhu  x11, 2(x1)
        u_imem.mem[11] = 32'h0020_9603; // lh   x12, 2(x1)
        u_imem.mem[12] = 32'h0070_A223; // sw   x7, 4(x1)
        u_imem.mem[13] = 32'h0040_A683; // lw   x13, 4(x1)
        u_imem.mem[14] = 32'h0076_8463; // beq  x13, x7, +8
        u_imem.mem[15] = 32'h0000_A423; // sw   x0, 8(x1) WRONG PATH
        u_imem.mem[16] = 32'h0010_0073; // ebreak
        u_imem.mem[17] = 32'h0090_0713; // addi x14, x0, 9

        // Sentinel catches unintended wrong-path stores
        u_dmem.mem[2] = 32'hCAFE_BABE;

        repeat (3) @(negedge clk);
        rst = 1'b0;
    end

    // --------------------------------------------------------
    // Bus monitors and counters
    // --------------------------------------------------------

    int unsigned dmem_requests  = 0;
    int unsigned dmem_responses = 0;
    int unsigned stores        = 0;
    int unsigned loads         = 0;
    int unsigned stall_cycles  = 0;

    always @(posedge clk) begin
        if (!rst) begin

            if (dut.mem_stall)
                stall_cycles <= stall_cycles + 1;

            // Instruction bus should be read only
            if (imem_bus.req_valid &&
                imem_bus.req_ready &&
                imem_bus.req_write)
                $fatal(1, "Instruction bus attempted a write");

            if (dmem_bus.req_valid && dmem_bus.req_ready) begin
                dmem_requests <= dmem_requests + 1;

                $display(
                    "[DMEM REQ] addr=%08h write=%b strb=%04b data=%08h",
                    dmem_bus.req_addr,
                    dmem_bus.req_write,
                    dmem_bus.req_wstrb,
                    dmem_bus.req_wdata
                );

                if (dmem_bus.req_write) begin
                    stores <= stores + 1;

                    // Check write addresses and active byte lanes
                    case (dmem_bus.req_addr)

                        32'h0000_1000: begin
                            if (dmem_bus.req_wstrb !== 4'b1111 ||
                                dmem_bus.req_wdata !== 32'd42)
                                $fatal(1, "SW x5 request incorrect");
                        end

                        32'h0000_1001: begin
                            if (dmem_bus.req_wstrb !== 4'b0010 ||
                                dmem_bus.req_wdata[15:8] !== 8'hFF)
                                $fatal(1, "SB request incorrect");
                        end

                        32'h0000_1002: begin
                            if (dmem_bus.req_wstrb !== 4'b1100 ||
                                dmem_bus.req_wdata[31:16] !== 16'hFFFF)
                                $fatal(1, "SH request incorrect");
                        end

                        32'h0000_1004: begin
                            if (dmem_bus.req_wstrb !== 4'b1111 ||
                                dmem_bus.req_wdata !== 32'd84)
                                $fatal(1, "SW x7 request incorrect");
                        end

                        default:
                            $fatal(1, "Unexpected store address");

                    endcase

                end
                else begin
                    loads <= loads + 1;

                    if (dmem_bus.req_wstrb !== 4'b0000)
                        $fatal(1, "Load has nonzero write strobes");
                end
            end

            if (dmem_bus.rsp_valid && dmem_bus.rsp_ready) begin
                dmem_responses <= dmem_responses + 1;

                if (dmem_bus.rsp_err)
                    $fatal(1, "Unexpected data bus error");
            end
        end
    end

    // --------------------------------------------------------
    // Retirement checker
    // --------------------------------------------------------

    task automatic expect_rd(
        input reg_addr_t expected_rd,
        input word_t expected_data
    );
        if (rvfi.rd_addr !== expected_rd ||
            rvfi.rd_wdata !== expected_data)
            $fatal(1,
                "Incorrect writeback at PC=%08h: rd=x%0d data=%08h, expected x%0d=%08h",
                rvfi.pc_rdata,
                rvfi.rd_addr, rvfi.rd_wdata,
                expected_rd, expected_data
            );
    endtask

    int unsigned retired = 0;
    int unsigned settle_cycles = 0;
    word_t expected_pc;

    initial begin
        forever begin
            @(negedge clk);

            if (!rst) begin

                if (fetch_error)
                    $fatal(1, "Unexpected instruction fetch error");

                if (data_access_fault)
                    $fatal(1, "Unexpected data access fault");

                if (rvfi.valid) begin

                    if (rvfi.order !== 64'(retired))
                        $fatal(1, "Retirement order mismatch");

                    if (retired > 15)
                        $fatal(1, "Unexpected extra retirement");

                    expected_pc =
                        (retired == 15)
                        ? 32'h0000_0040
                        : 32'(retired * 4);

                    if (rvfi.pc_rdata !== expected_pc)
                        $fatal(1,
                            "PC mismatch: got %08h, expected %08h",
                            rvfi.pc_rdata, expected_pc
                        );

                    // No instruction before EBREAK should trap
                    if (retired != 15 && rvfi.trap)
                        $fatal(1, "Unexpected architectural trap");

                    case (retired)

                        0: expect_rd(5'd1,  32'h0000_1000);
                        1: expect_rd(5'd5,  32'd42);
                        3: expect_rd(5'd6,  32'd42);
                        4: expect_rd(5'd7,  32'd84);
                        5: expect_rd(5'd8,  32'hFFFF_FFFF);
                        7: expect_rd(5'd9,  32'd255);
                        8: expect_rd(5'd10, 32'hFFFF_FFFF);
                        10: expect_rd(5'd11, 32'd65535);
                        11: expect_rd(5'd12, 32'hFFFF_FFFF);
                        13: expect_rd(5'd13, 32'd84);

                        14: begin
                            if (rvfi.pc_wdata !== 32'h40)
                                $fatal(1, "Branch target incorrect");
                        end

                        15: begin
                            if (!rvfi.trap)
                                $fatal(1, "EBREAK did not trap");
                        end

                        default: begin
                            // Stores do not produce register writes
                        end

                    endcase

                    $display(
                        "[RETIRE] order=%0d pc=%08h insn=%08h rd=x%0d data=%08h",
                        rvfi.order,
                        rvfi.pc_rdata,
                        rvfi.insn,
                        rvfi.rd_addr,
                        rvfi.rd_wdata
                    );

                    retired++;
                end

                // After EBREAK, allow time to catch accidental
                // duplicate retirement or late wrong-path writes
                if (retired == 16) begin
                    settle_cycles++;

                    if (settle_cycles == 20) begin

                        if (u_dmem.mem[0] !== 32'hFFFF_FF2A)
                            $fatal(1, "Final memory word 0 incorrect");

                        if (u_dmem.mem[1] !== 32'd84)
                            $fatal(1, "Final memory word 1 incorrect");

                        if (u_dmem.mem[2] !== 32'hCAFE_BABE)
                            $fatal(1, "Wrong-path store modified memory");

                        if (dmem_requests != 10 ||
                            dmem_responses != 10)
                            $fatal(1,
                                "Data bus handshake count mismatch");

                        if (stores != 4 || loads != 6)
                            $fatal(1, "Load/store counts incorrect");

                        if (stall_cycles < 20)
                            $fatal(1, "Expected memory stalls not observed");

                        $display(
                            "[BUS] requests=%0d responses=%0d stores=%0d loads=%0d stalled_cycles=%0d",
                            dmem_requests,
                            dmem_responses,
                            stores,
                            loads,
                            stall_cycles
                        );

                        $display("[PASS] Dual-bus CPU integration");
                        $finish;
                    end
                end
            end
        end
    end

    // --------------------------------------------------------
    // Simulation timeout
    // --------------------------------------------------------

    initial begin : timeout_watchdog
        repeat (1600) @(negedge clk);

        $fatal(1,
            "Timeout: only %0d/16 instructions retired",
            retired
        );
    end

endmodule
