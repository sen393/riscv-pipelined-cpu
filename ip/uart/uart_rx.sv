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

endmodule
