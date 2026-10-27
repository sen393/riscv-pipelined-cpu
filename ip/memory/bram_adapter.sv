module bram_adapter #(
    parameter int unsigned      DEPTH_WORDS = 1024,
    parameter logic [31:0]      BASE_ADDR   = 32'h0000_0000,
    parameter string            INIT_FILE   = "",
    parameter bit               READ_ONLY   = 1'b0
)(
    input   logic       clk,
    input   logic       rst,

    mem_bus_if.slave    bus
);

    localparam int unsigned ADDR_W = $clog2(DEPTH_WORDS);
    localparam int unsigned DATA_W = 32;

    // --------------------------------------------------------
    // FSM states
    // --------------------------------------------------------

    typedef enum logic {
        ADAPTER_IDLE,
        ADAPTER_RSP
    } state_e;

    state_e state_q;


    // --------------------------------------------------------
    // Internal signals
    // --------------------------------------------------------

    logic               req_fire;
    logic               addr_valid;
    logic               req_error;

    logic [31:0]        addr_offset;

    logic               bram_en;
    logic [3:0]         bram_we;
    logic [ADDR_W-1:0]  bram_addr;
    logic [DATA_W-1:0]  bram_rdata;

    logic               rsp_error_q;
    logic               rsp_write_q;


    // --------------------------------------------------------
    // Address translation and validation
    // --------------------------------------------------------

    assign addr_offset  = bus.req_addr - BASE_ADDR;
    
    // Cannot access word addr beyond DEPTH
    assign addr_valid   =
        (bus.req_addr >= BASE_ADDR) &&
        ((addr_offset >> 2) < DEPTH_WORDS);
    
    // Convert byte addr to word addr (divide by 4)
    assign bram_addr    = addr_offset >> 2;

    assign req_error    =
        !addr_valid ||
        (READ_ONLY && bus.req_write);   // READ ONLY cannot write


    // --------------------------------------------------------
    // Bus req handshake
    // --------------------------------------------------------

    assign bus.req_ready = (state_q == ADAPTER_IDLE) && !rst;
    assign req_fire = bus.req_valid && bus.req_ready;


    // --------------------------------------------------------
    // BRAM
    // --------------------------------------------------------

    // Only access mem for valid, accepted reqs
    assign bram_en = req_fire && !req_error;
    assign bram_we = (bus.req_write) ? bus.req_wstrb : 4'b0000;

    bram #(
        .DEPTH_WORDS    (DEPTH_WORDS),
        .DATA_W         (DATA_W),
        .INIT_FILE      (INIT_FILE)
    ) u_bram (
        .clk            (clk),
        // Memory controls
        .en             (bram_en),
        .we             (bram_we),
        // Memory addr
        .addr           (bram_addr),
        // Data
        .wdata          (bus.req_wdata),
        .rdata          (bram_rdata)
    );


    // --------------------------------------------------------
    // Adapter FSM
    // --------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q     <= ADAPTER_IDLE;
            rsp_error_q <= 1'b0;
            rsp_write_q <= 1'b0;
        end
        else begin
            case (state_q)

                ADAPTER_IDLE : begin
                    if (req_fire) begin
                        rsp_error_q <= req_error;
                        rsp_write_q <= bus.req_write;
                        state_q     <= ADAPTER_RSP;
                    end 
                end

                ADAPTER_RSP  : begin
                    if (bus.rsp_valid && bus.rsp_ready)
                        state_q <= ADAPTER_IDLE;
                end

                default      : begin
                    state_q <= ADAPTER_IDLE;
                end

            endcase
        end
    end


    // --------------------------------------------------------
    // Bus response
    // --------------------------------------------------------

    assign bus.rsp_valid = (state_q == ADAPTER_RSP) && !rst;
    assign bus.rsp_err   = bus.rsp_valid && rsp_error_q;

    // Only read reqs can return data
    assign bus.rsp_rdata =
        (bus.rsp_valid && !rsp_error_q && !rsp_write_q)
        ? bram_rdata
        : '0;


endmodule
