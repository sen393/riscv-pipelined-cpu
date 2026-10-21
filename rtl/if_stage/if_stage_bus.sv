module if_stage_bus
    import riscv_pkg::*;
#(
    parameter logic [XLEN-1:0] RESET_PC = '0
)(
    input   logic               clk,
    input   logic               rst,

    // Pipeline control
    input   logic               decode_ready,
    input   logic               stop_fetch,
    
    // Control-flow redirect from later stage
    input   logic               redirect_valid,
    input   logic [XLEN-1:0]    redirect_pc,

    // Instruction memory interface
    mem_bus_if.master         imem,

    // Output to IF/ID pipeline register
    output  if_id_t             if_id_d,

    output  logic               fetch_error 
);

    // --------------------------------------------------------
    // Fetch state machine
    // --------------------------------------------------------

    typedef enum logic [1:0] {
        FETCH_IDLE,
        FETCH_REQ,
        FETCH_RSP,
        FETCH_HALT
    } fetch_state_e;

    fetch_state_e state_q;


    // --------------------------------------------------------
    // Internal regs/signals
    // --------------------------------------------------------

    addr_t  req_pc_q;   // Current requester pc
    addr_t  next_pc_q;  // Next pc

    logic   discard_q;  // req belongs to obsolete path
    logic   halt_pending_q; // Halt requested, drain fetch

    logic   req_fire;
    logic   rsp_fire;
    logic   discard_response;


    // --------------------------------------------------------
    // Instruction request channel
    // --------------------------------------------------------

    assign imem.req_valid   = (state_q == FETCH_REQ) && !rst;
    assign imem.req_addr    = req_pc_q;

    // Instruction memory is read-only
    assign imem.req_write   = 1'b0;
    assign imem.req_wdata   = '0;
    assign imem.req_wstrb   = '0;

    assign req_fire = imem.req_valid && imem.req_ready;


    // --------------------------------------------------------
    // Instruction response channel
    // --------------------------------------------------------

    assign  discard_response =
            discard_q       ||
            halt_pending_q  ||
            redirect_valid  ||
            stop_fetch;

    // Accept rsp when decode is ready
    // Consume discarded or errored rsp
    assign  imem.rsp_ready   =
            (state_q == FETCH_RSP) &&
            (decode_ready || discard_response || imem.rsp_err);

    assign rsp_fire = imem.rsp_valid && imem.rsp_ready;


    // --------------------------------------------------------
    // IF -> ID Bundle
    // --------------------------------------------------------

    always_comb begin
        if_id_d             = '0; 

        if (rsp_fire && !discard_response && !imem.rsp_err) begin
            if_id_d.valid       = 1'b1;
            if_id_d.pc          = req_pc_q;
            if_id_d.pc_plus4    = req_pc_q + 32'd4;
            if_id_d.instr       = imem.rsp_rdata;
        end
    end


    // --------------------------------------------------------
    // Fetch control and PC tracking
    // --------------------------------------------------------

    always_ff @(posedge clk) begin

        if (rst) begin
            state_q         <= FETCH_IDLE;
            req_pc_q        <= RESET_PC;
            next_pc_q       <= RESET_PC + 32'd4;

            discard_q       <= 1'b0;
            halt_pending_q  <= 1'b0;
            fetch_error     <= 1'b0;
        end
        else begin
            if (redirect_valid)
                next_pc_q   <= redirect_pc;

            if (stop_fetch)
                halt_pending_q  <= 1'b1;
            
            case (state_q)

                // --------------------------------------------
                // Send instruction fetch
                // --------------------------------------------
                FETCH_IDLE: begin
                    if (stop_fetch || halt_pending_q) begin
                        state_q <= FETCH_HALT;
                    end
                    else begin
                        state_q <= FETCH_REQ;

                        // Redirect directly if no request is pending
                        if (redirect_valid) begin
                            req_pc_q  <= redirect_pc;
                            next_pc_q <= redirect_pc + 32'd4;
                        end
                    end
                end
                FETCH_REQ: begin
                    if (redirect_valid)
                        discard_q   <= 1'b1;

                    if (req_fire)
                        state_q     <= FETCH_RSP;
                end

                // --------------------------------------------
                // Wait for instruction response
                // --------------------------------------------
                FETCH_RSP: begin
                    if (redirect_valid)
                        discard_q   <= 1'b1;
                    
                    if (rsp_fire) begin
                        discard_q   <= 1'b0;

                        if (halt_pending_q || stop_fetch || 
                            (imem.rsp_err && !discard_response)) begin
                            if (imem.rsp_err && !discard_response)
                                fetch_error <= 1'b1;
                            state_q <= FETCH_HALT;
                        end
                        else begin
                            state_q     <= FETCH_IDLE;
                            req_pc_q    <= (redirect_valid) ? redirect_pc : next_pc_q;
                            next_pc_q   <= ((redirect_valid) ? redirect_pc : next_pc_q) + 32'd4;
                        end
                    end
                end

                // --------------------------------------------
                // Terminal halt, requires rst to restart
                // --------------------------------------------
                FETCH_HALT: begin
                    // Do nothing
                end

                default: begin
                    state_q <= FETCH_HALT;
                end

            endcase
        end

    end


endmodule

