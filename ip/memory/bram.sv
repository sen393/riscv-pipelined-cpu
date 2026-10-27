module bram #(
    parameter int unsigned      DEPTH_WORDS = 1024,
    parameter int unsigned      DATA_W      = 32,
    parameter string            INIT_FILE   = "",
    localparam int unsigned     ADDR_W = $clog2(DEPTH_WORDS)
)(
    input   logic   clk,

    // Memory controls
    input   logic                   en,
    input   logic [DATA_W/8 -1 : 0] we,

    // Memory addr
    input   logic [ADDR_W-1 : 0]    addr,

    // Data
    input   logic [DATA_W-1 : 0]    wdata,
    output  logic [DATA_W-1 : 0]    rdata
);

    // --------------------------------------------------------
    // Block RAM Storage
    // --------------------------------------------------------

    (* ram_style = "block" *)
    logic [DATA_W-1 : 0] mem [0 : DEPTH_WORDS-1];

    // Optional mem init
    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end


    // --------------------------------------------------------
    // Synch read/write
    // --------------------------------------------------------

    always_ff @(posedge clk) begin
        if (en) begin
            // Read first
            rdata <= mem[addr];

            // Independent byte write enables
            for (int i = 0; i < (DATA_W/8); i++) begin
                if (we[i])
                    mem[addr][8*i +: 8] <= wdata[8*i +:8];
            end
        end
    end

endmodule
