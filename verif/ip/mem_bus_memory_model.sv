
module mem_bus_memory_model #(
    parameter int unsigned DEPTH_WORDS  = 64,
    parameter logic [31:0] BASE_ADDR    = 32'h0001_0000
)(
    mem_bus_if.slave    bus,

    // Testbench-controlled response delay
    input logic [7:0]   response_delay
);

    // --------------------------------------------------------
    // Memory state machine
    // --------------------------------------------------------

    typedef enum logic [1:0] {
        IDLE,
        WAIT_RESPONSE,
        SEND_RESPONSE
    } state_t;

    state_t state_q;

    // --------------------------------------------------------
    // Internal registers
    // --------------------------------------------------------

    logic [7:0]  wait_left_q;
    logic [31:0] response_data_q;
    logic        response_err_q;

    // Memory array: DEPTH_WORDS x 32 bits
    logic [31:0] mem [0:DEPTH_WORDS-1];

    // Initialize memory contents
    initial begin
        for (int i = 0; i < DEPTH_WORDS; i++)
            mem[i] = '0;
    end

    // --------------------------------------------------------
    // Bus handshake signals
    // --------------------------------------------------------

    assign bus.req_ready = (state_q == IDLE);

    assign bus.rsp_valid = (state_q == SEND_RESPONSE);
    assign bus.rsp_rdata = response_data_q;
    assign bus.rsp_err   = response_err_q;

    // --------------------------------------------------------
    // Memory state machine
    // --------------------------------------------------------

    always_ff @(posedge bus.clk) begin : memory_fsm

        logic        in_range;
        logic [31:0] offset;
        int unsigned word_index;

        if (bus.rst) begin
            state_q         <= IDLE;
            wait_left_q     <= '0;
            response_data_q <= '0;
            response_err_q  <= 1'b0;
        end
        else begin
            case (state_q)

                // --------------------------------------------
                // Accept request
                // --------------------------------------------
                IDLE: begin
                    if (bus.req_valid && bus.req_ready) begin

                        offset = bus.req_addr - BASE_ADDR;

                        in_range =
                            (bus.req_addr >= BASE_ADDR) &&
                            (offset < 4 * DEPTH_WORDS);

                        word_index = offset >> 2;

                        response_err_q  <= !in_range;
                        response_data_q <= '0;

                        if (in_range) begin

                            if (bus.req_write) begin

                                for (int lane = 0; lane < 4; lane++) begin
                                    if (bus.req_wstrb[lane])
                                        mem[word_index][8*lane +: 8]
                                            <= bus.req_wdata[8*lane +: 8];
                                end

                            end
                            else begin
                                response_data_q <= mem[word_index];
                            end

                        end

                        wait_left_q <= response_delay;

                        state_q <= (response_delay == 0)
                                   ? SEND_RESPONSE
                                   : WAIT_RESPONSE;
                    end
                end

                // --------------------------------------------
                // Simulate memory latency
                // --------------------------------------------
                WAIT_RESPONSE: begin

                    if (wait_left_q == 8'd1) begin
                        wait_left_q <= '0;
                        state_q <= SEND_RESPONSE;
                    end
                    else begin
                        wait_left_q <= wait_left_q - 8'd1;
                    end

                end

                // --------------------------------------------
                // Wait for CPU to accept response
                // --------------------------------------------
                SEND_RESPONSE: begin

                    if (bus.rsp_valid && bus.rsp_ready)
                        state_q <= IDLE;

                end

                default: state_q <= IDLE;

            endcase
        end
    end

endmodule
