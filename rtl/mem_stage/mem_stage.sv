module mem_stage
    import riscv_pkg::*;
#(
    parameter int unsigned DMEM_DEPTH = 256
)
(
    input   logic       clk,

    // From EX/MEM pipeline reg
    input   ex_mem_t    ex_mem_q,

    // To MEM/WB pipeline reg
    output  mem_wb_t    mem_wb_d
);

    word_t          mem_read_data;
    word_t          load_data;

    logic   [7:0]   load_byte;
    logic   [15:0]  load_half;

    logic           mem_write_en;

    logic           mem_read_en;
    byte_mask_t     mem_mask;


    // --------------------------------------------------------
    // Memory read/write enable
    // --------------------------------------------------------

    assign mem_write_en = ex_mem_q.valid && ex_mem_q.ctrl.mem_write;
    assign mem_read_en  = ex_mem_q.valid && ex_mem_q.ctrl.mem_read;


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
    // Data memory
    // --------------------------------------------------------

    data_mem #(
        .DEPTH      (DMEM_DEPTH)
    ) u_data_mem (
        .clk        (clk),
        .write_en   (mem_write_en),
        .mem_size   (ex_mem_q.ctrl.mem_size),
        .addr       (ex_mem_q.alu_result),
        .write_data (ex_mem_q.store_data),
        .read_data  (mem_read_data)
    );


    // --------------------------------------------------------
    // Load byte selection
    // --------------------------------------------------------

    always_comb begin
        case (ex_mem_q.alu_result[1:0])

            2'b00   : load_byte = mem_read_data[7:0];
            2'b01   : load_byte = mem_read_data[15:8];
            2'b10   : load_byte = mem_read_data[23:16];
            2'b11   : load_byte = mem_read_data[31:24];
            default : ;

        endcase
    end


    // --------------------------------------------------------
    // Load half selection
    // --------------------------------------------------------

    always_comb begin
        case (ex_mem_q.alu_result[1])

            1'b0    : load_half = mem_read_data[15:0];
            1'b1    : load_half = mem_read_data[31:16];
            default : ;

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

        if (ex_mem_q.valid) begin
            // Propagate metadata
            mem_wb_d.meta = ex_mem_q.meta;

            if (mem_read_en || mem_write_en) begin
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
                mem_wb_d.meta.mem_wdata =
                    ex_mem_q.store_data << (8 * ex_mem_q.alu_result[1:0]);
            end
        end
    end


endmodule

