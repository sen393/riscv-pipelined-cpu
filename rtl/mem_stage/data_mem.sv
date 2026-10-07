module data_mem
    import riscv_pkg::*;
#(
    parameter int unsigned DEPTH = 256
)(
    input   logic       clk,

    input   logic       write_en,
    input   mem_size_e  mem_size,

    input   word_t      addr,
    input   word_t      write_data,

    output  word_t      read_data
);

    localparam int unsigned ADDR_WIDTH = $clog2(DEPTH);

    word_t mem [0:DEPTH-1];

    logic [ADDR_WIDTH-1:0] word_addr;

    // Ignore bottom 2 bits since each entry is 4 bytes
    assign word_addr = addr[ADDR_WIDTH+1:2];

    // Asynchronous data read
    assign read_data = mem[word_addr];

    // Mem write
    always_ff @( posedge clk ) begin
        if (write_en) begin
            case (mem_size)

                MEM_BYTE    : begin
                    case (addr[1:0])
                        2'b00: mem[word_addr][7:0]      <= write_data[7:0];
                        2'b01: mem[word_addr][15:8]     <= write_data[7:0];
                        2'b10: mem[word_addr][23:16]    <= write_data[7:0];
                        2'b11: mem[word_addr][31:24]    <= write_data[7:0];
                    endcase
                end

                MEM_HALF    : begin
                    case (addr[1])
                        1'b0:  mem[word_addr][15:0]     <= write_data[15:0];
                        1'b1:  mem[word_addr][31:16]    <= write_data[15:0];
                    endcase
                end

                MEM_WORD    : begin
                    mem[word_addr]  <= write_data;
                end

                default     : ;
                
            endcase
        end
    end

endmodule

