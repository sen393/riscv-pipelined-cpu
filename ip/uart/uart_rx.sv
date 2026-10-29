module uart_rx #(
    parameter int unsigned CLK_HZ = 80_000_000,
    parameter int unsigned BAUD   = 115_200
)(
    input  logic       clk,
    input  logic       rst,

    input  logic       rx,

    output logic       rx_valid,
    output logic [7:0] rx_data,
    output logic       frame_error
);

    // --------------------------------------------------------
    // Baud timing
    // --------------------------------------------------------

    localparam int unsigned CLKS_PER_BIT =
        (CLK_HZ + BAUD / 2) / BAUD;

    localparam int unsigned HALF_CLKS_PER_BIT =
        CLKS_PER_BIT / 2;

    localparam int unsigned COUNT_W =
        $clog2(CLKS_PER_BIT);

    localparam logic [COUNT_W-1:0] LAST_COUNT = 
        COUNT_W'(CLKS_PER_BIT - 1);

    localparam logic [COUNT_W-1:0] HALF_LAST_COUNT =
        COUNT_W'(HALF_CLKS_PER_BIT - 1);


    // --------------------------------------------------------
    // Asynchronous input synchronizer
    // --------------------------------------------------------

    (* ASYNC_REG = "TRUE" *) logic rx_meta_q;
    (* ASYNC_REG = "TRUE" *) logic rx_sync_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_meta_q <= 1'b1;
            rx_sync_q <= 1'b1;
        end else begin
            rx_meta_q <= rx;
            rx_sync_q <= rx_meta_q;
        end
    end


    // --------------------------------------------------------
    // FSM states and frame regs
    // --------------------------------------------------------

    typedef enum logic [1:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_STOP,
        RX_WAIT_HIGH
    } state_e;

    state_e state_q;

    logic [COUNT_W-1:0] baud_count_q;
    logic [7:0]         data_q;
    logic [2:0]         bit_q;


    // --------------------------------------------------------
    // Receiver state machine
    // --------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q         <= RX_IDLE;
            data_q          <= '0;
            baud_count_q    <= '0;
            bit_q           <= '0;

            rx_valid        <= 1'b0;
            rx_data         <= '0;
            frame_error     <= '0;
        end else begin
            rx_valid        <= 1'b0;
            frame_error     <= 1'b0;

            case (state_q)

                RX_IDLE  : begin
                    baud_count_q <= '0;
                    bit_q        <= '0;
                    if (!rx_sync_q)
                        state_q <= RX_START;
                end

                RX_START : begin
                    if (baud_count_q == HALF_LAST_COUNT) begin
                        if (!rx_sync_q) // rx still 0, start
                            state_q <= RX_DATA;
                        else            // rx is 1, false start
                            state_q <= RX_IDLE;
                    end else begin
                        baud_count_q <= baud_count_q + 1'd1;
                    end
                end

                RX_DATA  : begin
                    if (baud_count_q == LAST_COUNT) begin
                        baud_count_q <= '0;
                        data_q[bit_q] <= rx_sync_q;

                        if (bit_q == 3'd7) begin
                            state_q <= RX_STOP;
                        end else begin
                            bit_q <= bit_q + 3'd1;
                        end
                    end else begin
                        baud_count_q <= baud_count_q + 1'd1;
                    end
                end

                RX_STOP  : begin
                    if (baud_count_q == LAST_COUNT) begin
                        baud_count_q <= '0;
                        if (rx_sync_q) begin
                            rx_data     <= data_q;
                            rx_valid    <= 1'b1;
                            state_q     <= RX_IDLE;
                        end else begin
                            frame_error <= 1'b1;
                            state_q     <= RX_WAIT_HIGH;
                        end
                    end else begin
                        baud_count_q <= baud_count_q + 1'd1;
                    end
                end

                RX_WAIT_HIGH : begin
                    baud_count_q <= '0;
                    if (rx_sync_q)
                        state_q <= RX_IDLE;
                end

                default  : begin
                    state_q         <= RX_IDLE;
                    data_q          <= '0;
                    baud_count_q    <= '0;
                    bit_q           <= '0;
                end

            endcase
        end
    end
endmodule
