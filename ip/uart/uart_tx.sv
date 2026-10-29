module uart_tx #(
    parameter int unsigned CLK_HZ = 80_000_000,
    parameter int unsigned BAUD   = 115_200
)(
    input  logic       clk,
    input  logic       rst,

    input  logic       tx_valid,
    output logic       tx_ready,
    input  logic [7:0] tx_data,

    output logic       tx
);

    // --------------------------------------------------------
    // Baud timing
    // --------------------------------------------------------

    localparam int unsigned CLKS_PER_BIT =
        (CLK_HZ + BAUD / 2) / BAUD;

    localparam int unsigned COUNT_W = $clog2(CLKS_PER_BIT);

    localparam logic [COUNT_W-1:0] LAST_COUNT = 
        COUNT_W'(CLKS_PER_BIT - 1);


    // --------------------------------------------------------
    // FSM states and frame regs
    // --------------------------------------------------------

    typedef enum logic [1:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_STOP
    } state_e;

    state_e state_q;

    logic [COUNT_W-1:0] baud_count_q;
    logic [7:0]         data_q;
    logic [2:0]         bit_q;

    bit     tx_fire;

    // --------------------------------------------------------
    // Input handshake
    // --------------------------------------------------------

    assign tx_fire  = tx_valid && tx_ready;
    assign tx_ready = !rst && (state_q == TX_IDLE);


    // --------------------------------------------------------
    // Transmitter state machine
    // --------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q         <= TX_IDLE;
            data_q          <= '0;
            bit_q           <= '0;
            baud_count_q    <= '0;
            tx              <= 1'b1;
        end 
        else begin
            case (state_q)

                TX_IDLE  : begin
                    tx              <= 1'b1; 
                    baud_count_q    <= '0;
                    bit_q           <= '0;

                    if (tx_fire) begin
                        tx          <= 1'b0;
                        data_q      <= tx_data;
                        state_q     <= TX_START;
                    end
                end

                TX_START : begin
                    if (baud_count_q == LAST_COUNT) begin
                        baud_count_q <= '0;
                        tx           <= data_q[0];
                        state_q      <= TX_DATA;
                    end else begin
                        baud_count_q <= baud_count_q + 1'd1;
                    end
                end

                TX_DATA  : begin
                    if (baud_count_q == LAST_COUNT) begin

                        baud_count_q <= '0;

                        if (bit_q == 3'd7) begin
                            tx      <= 1'b1;
                            state_q <= TX_STOP;
                        end else begin
                            bit_q   <= bit_q + 3'd1;
                            tx      <= data_q[bit_q + 3'd1];
                        end
                    end

                    else begin
                        baud_count_q <= baud_count_q + 1'd1;
                    end
                end

                TX_STOP  : begin
                    if (baud_count_q == LAST_COUNT) begin
                        baud_count_q <= '0;
                        state_q      <= TX_IDLE;
                    end else begin
                        baud_count_q <= baud_count_q + 1'd1;
                    end
                end

                default  : begin
                    state_q         <= TX_IDLE;
                    data_q          <= '0;
                    bit_q           <= '0;
                    baud_count_q    <= '0;
                    tx              <= 1'b1;
                end

            endcase
        end
    end

endmodule
