
module processor_ifbus_tb;
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
    // Instruction bus
    // --------------------------------------------------------

    mem_bus_if imem_bus (
        .clk (clk),
        .rst (rst)
    );

    retire_t rvfi;
    logic fetch_error;

    logic [7:0] response_delay;

    // Longer delay for the wrong-path instruction
    assign response_delay =
        (imem_bus.req_addr == 32'h0000_000C)
            ? 8'd6
            : 8'd2;

    // --------------------------------------------------------
    // DUT
    // --------------------------------------------------------

    riscv_core_ifbus dut (
        .clk         (clk),
        .rst         (rst),
        .imem        (imem_bus),
        .rvfi        (rvfi),
        .fetch_error (fetch_error)
    );

    // --------------------------------------------------------
    // Instruction memory model
    // --------------------------------------------------------

    mem_bus_memory_model #(
        .DEPTH_WORDS (64),
        .BASE_ADDR   (32'h0000_0000)
    ) u_imem (
        .bus            (imem_bus),
        .response_delay (response_delay)
    );

    // --------------------------------------------------------
    // Program initialization
    // --------------------------------------------------------

    initial begin
        @(negedge clk);

        u_imem.mem[0] = 32'h0050_0093; // addi x1, x0, 5
        u_imem.mem[1] = 32'h0070_8113; // addi x2, x1, 7
        u_imem.mem[2] = 32'h0021_0463; // beq x2, x2, +8
        u_imem.mem[3] = 32'h0630_0193; // addi x3, x0, 99
        u_imem.mem[4] = 32'h0031_0213; // addi x4, x2, 3
        u_imem.mem[5] = 32'h0010_0073; // ebreak
        u_imem.mem[6] = 32'h04D0_0393; // addi x7, x0, 77

        repeat (3) @(negedge clk);
        rst = 1'b0;
    end

    // --------------------------------------------------------
    // Bus and redirect monitoring
    // --------------------------------------------------------

    int unsigned req_count = 0;
    int unsigned rsp_count = 0;
    bit saw_redirect = 1'b0;

    always @(posedge clk) begin
        if (!rst) begin

            if (imem_bus.req_valid && imem_bus.req_ready) begin
                req_count++;

                if (imem_bus.req_write)
                    $fatal(1, "Instruction bus issued a write");

                $display("[IF REQ] PC=%08h", imem_bus.req_addr);
            end

            if (imem_bus.rsp_valid && imem_bus.rsp_ready) begin
                rsp_count++;
            end

            if (dut.redirect_valid) begin
                saw_redirect = 1'b1;
                $display("[REDIRECT] PC=%08h", dut.redirect_pc);
            end
        end
    end

    // --------------------------------------------------------
    // Retirement scoreboard
    // --------------------------------------------------------

    int unsigned retire_count = 0;
    int unsigned settle_cycles = 0;

    always @(negedge clk) begin
        if (!rst) begin

            if (fetch_error)
                $fatal(1, "Unexpected instruction fetch error");

            if (rvfi.valid) begin

                if (rvfi.order !== 64'(retire_count))
                    $fatal(1, "Incorrect retirement order");

                case (retire_count)

                    0: begin
                        if (rvfi.pc_rdata !== 32'h0 ||
                            rvfi.rd_addr  !== 5'd1 ||
                            rvfi.rd_wdata !== 32'd5)
                            $fatal(1, "Instruction 0 failed");
                    end

                    1: begin
                        if (rvfi.pc_rdata !== 32'h4 ||
                            rvfi.rd_addr  !== 5'd2 ||
                            rvfi.rd_wdata !== 32'd12)
                            $fatal(1, "Instruction 1 failed");
                    end

                    2: begin
                        if (rvfi.pc_rdata !== 32'h8 ||
                            rvfi.pc_wdata !== 32'h10)
                            $fatal(1, "Branch failed");
                    end

                    3: begin
                        if (rvfi.pc_rdata !== 32'h10 ||
                            rvfi.rd_addr  !== 5'd4 ||
                            rvfi.rd_wdata !== 32'd15)
                            $fatal(1, "Branch target failed");
                    end

                    4: begin
                        if (rvfi.pc_rdata !== 32'h14 ||
                            !rvfi.trap)
                            $fatal(1, "EBREAK failed");
                    end

                    default:
                        $fatal(1, "Unexpected instruction retired");

                endcase

                $display(
                    "[RETIRE] order=%0d pc=%08h instr=%08h",
                    rvfi.order,
                    rvfi.pc_rdata,
                    rvfi.insn
                );

                retire_count++;
            end

            // Allow time to detect unexpected retirement
            // after the terminal EBREAK.
            if (retire_count == 5) begin
                settle_cycles++;

                if (settle_cycles == 20) begin
                    if (!saw_redirect)
                        $fatal(1, "No branch redirect observed");

                    $display(
                        "[BUS] Requests=%0d Responses=%0d",
                        req_count, rsp_count
                    );

                    $display("[PASS] CPU instruction bus integration");
                    $finish;
                end
            end
        end
    end

    // --------------------------------------------------------
    // Timeout
    // --------------------------------------------------------

    initial begin
        repeat (400) @(negedge clk);
        $fatal(1, "Timeout: retired %0d instructions", retire_count);
    end

endmodule
