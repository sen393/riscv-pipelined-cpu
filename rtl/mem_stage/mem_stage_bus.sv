module mem_stage_bus
    import riscv_pkg::*;
(
    input   logic       clk,
    input   logic       rst,

    // From EX/MEM pipeline reg
    input   ex_mem_t    ex_mem_q,

    // Data memory bus
    mem_bus_if.master   dmem,

    // To MEM/WB pipeline reg
    output  mem_wb_t    mem_wb_d,

    // Pipeline control
    output  logic       mem_stall,
    output  logic       access_fault
);

    // --------------------------------------------------------
    // Memory FSM states
    // --------------------------------------------------------

    typedef enum logic [1:0] {
        MEM_IDLE,
        MEM_REQ,
        MEM_RSP,
        MEM_ERROR
    } mem_stage_e;

    mem_stage_e state_q;


    // --------------------------------------------------------
    // Internal signals
    // --------------------------------------------------------

    word_t          mem_read_data;
    word_t          load_data;

    logic   [7:0]   load_byte;
    logic   [15:0]  load_half;

    logic           mem_write_en;
    logic           mem_read_en;
    logic           mem_access;

    byte_mask_t     mem_mask;

    logic           req_fire;
    logic           rsp_fire;
    logic           mem_complete;


    // --------------------------------------------------------
    // Memory read/write enable
    // --------------------------------------------------------

    assign mem_write_en = ex_mem_q.valid && ex_mem_q.ctrl.mem_write;
    assign mem_read_en  = ex_mem_q.valid && ex_mem_q.ctrl.mem_read;

    assign mem_access   = mem_write_en || mem_read_en;


    // --------------------------------------------------------
    // Generate byte mask
    // --------------------------------------------------------

    always_comb begin
        case (ex_mem_q.ctrl.mem_size)
            MEM_BYTE    :   mem_mask = 4'b0001;
            MEM_HALF    :   mem_mask = 4'b0011;
            MEM_WORD    :   mem_mask = 4'b1111;
            default     :   mem_mask = 4'b0000;
        endcase

        mem_mask = mem_mask << ex_mem_q.alu_result[1:0];

    end


    // --------------------------------------------------------
    // Data memory request
    // --------------------------------------------------------

    assign dmem.req_valid   = (state_q == MEM_REQ) && !rst;
    assign dmem.req_addr    = ex_mem_q.alu_result;

    assign dmem.req_write   = mem_write_en;

    // Align store data to desired byte lanes
    assign dmem.req_wdata   = ex_mem_q.store_data <<
                            (8 * ex_mem_q.alu_result[1:0]);
    assign dmem.req_wstrb   = (mem_write_en) ? mem_mask : '0;

    assign req_fire         = dmem.req_valid && dmem.req_ready;


    // --------------------------------------------------------
    // Data memory response
    // --------------------------------------------------------

    assign dmem.rsp_ready   = (state_q == MEM_RSP) && !rst;

    assign rsp_fire         = dmem.rsp_valid && dmem.rsp_ready;

    assign mem_complete     = (state_q == MEM_RSP) &&
                              rsp_fire             &&
                              !dmem.rsp_err;

    assign mem_read_data    = (mem_complete && mem_read_en)
                            ? dmem.rsp_rdata
                            : '0;

    // Hold mem instr until it completes
    // Bus error keeps the pipeline halted
    assign mem_stall        = (state_q == MEM_ERROR)    ||
                              (mem_access && !mem_complete);

    assign access_fault     = (state_q == MEM_ERROR)    ||
                              ((state_q == MEM_RSP)     &&
                              rsp_fire && dmem.rsp_err);


    // --------------------------------------------------------
    // Memory transaction FSM
    // --------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q <= MEM_IDLE;
        end
        else begin
            case (state_q)
                MEM_IDLE    : begin
                    if (mem_access)
                        state_q <= MEM_REQ;
                end

                MEM_REQ     : begin
                    if (req_fire)
                        state_q <= MEM_RSP;
                end

                MEM_RSP     : begin
                    if (rsp_fire) begin
                        if (dmem.rsp_err)
                            state_q <= MEM_ERROR;
                        else
                            state_q <= MEM_IDLE;
                    end
                end

                MEM_ERROR   : begin
                    // Do nothing, stuck here until reset
                end

                default     : state_q <= MEM_ERROR;
            endcase
        end
    end


    // --------------------------------------------------------
    // Load byte selection
    // --------------------------------------------------------

    always_comb begin
        case (ex_mem_q.alu_result[1:0])

            2'b00   : load_byte = mem_read_data[7:0];
            2'b01   : load_byte = mem_read_data[15:8];
            2'b10   : load_byte = mem_read_data[23:16];
            2'b11   : load_byte = mem_read_data[31:24];
            default : load_byte = '0;

        endcase
    end


    // --------------------------------------------------------
    // Load half selection
    // --------------------------------------------------------

    always_comb begin
        case (ex_mem_q.alu_result[1])

            1'b0    : load_half = mem_read_data[15:0];
            1'b1    : load_half = mem_read_data[31:16];
            default : load_half = '0;

        endcase
    end


    // --------------------------------------------------------
    // Load formatting/extension
    // --------------------------------------------------------

    always_comb begin
        load_data = '0;

        case (ex_mem_q.ctrl.mem_size)

            MEM_BYTE    : begin
                if (ex_mem_q.ctrl.load_unsigned)
                    load_data = {{24'd0}, load_byte};
                else
                    load_data = {{24{load_byte[7]}}, load_byte};
            end

            MEM_HALF    : begin
                if (ex_mem_q.ctrl.load_unsigned)
                    load_data = {{16'd0}, load_half};
                else
                    load_data = {{16{load_half[15]}}, load_half};
            end

            MEM_WORD    : begin
                load_data = mem_read_data;
            end

            default     : begin
                load_data = '0;
            end

        endcase
    end
    

    // --------------------------------------------------------
    // MEM -> WB Bundle
    // --------------------------------------------------------

    always_comb begin
        // initialize
        mem_wb_d = '0;
        if (ex_mem_q.valid &&
            (!mem_access || mem_complete) &&
            state_q != MEM_ERROR) begin

            mem_wb_d.valid      = ex_mem_q.valid;

            mem_wb_d.pc         = ex_mem_q.pc;
            mem_wb_d.pc_plus4   = ex_mem_q.pc_plus4;
            mem_wb_d.instr      = ex_mem_q.instr;

            mem_wb_d.rd         = ex_mem_q.rd;

            mem_wb_d.alu_result = ex_mem_q.alu_result;
            mem_wb_d.mem_data   = load_data;

            mem_wb_d.ctrl       = ex_mem_q.ctrl;

            // ----------------------------------------------------
            // Retirement Metadata
            // ----------------------------------------------------

            mem_wb_d.meta = ex_mem_q.meta;

            if (mem_access) begin
                mem_wb_d.meta.mem_addr = {
                    ex_mem_q.alu_result[XLEN-1:2],
                    2'b00
                };
            end

            if (mem_read_en) begin
                mem_wb_d.meta.mem_rmask = mem_mask;
                mem_wb_d.meta.mem_rdata = mem_read_data;
            end

            if (mem_write_en) begin
                mem_wb_d.meta.mem_wmask = mem_mask;
                mem_wb_d.meta.mem_wdata = dmem.req_wdata;
            end
        end
    end


endmodule

