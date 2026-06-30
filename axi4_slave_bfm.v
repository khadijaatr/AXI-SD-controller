// =============================================================
//  AXI4 Full Slave BFM
//  File    : axi4_slave_bfm.v
//  Features: Responds to single writes/reads, internal memory
//  Params  : DATA_W, ADDR_W, ID_W, MEM_DEPTH
// =============================================================

module axi4_slave_bfm #(
    parameter DATA_W    = 32,
    parameter ADDR_W    = 32,
    parameter ID_W      = 4,
    parameter MEM_DEPTH = 256       // number of words
)(
    input  wire                clk,
    input  wire                rst_n,

    // Write Address Channel (AW)
    input  wire [ID_W-1:0]     awid,
    input  wire [ADDR_W-1:0]   awaddr,
    input  wire [7:0]          awlen,
    input  wire [2:0]          awsize,
    input  wire [1:0]          awburst,
    input  wire                awlock,
    input  wire [3:0]          awcache,
    input  wire [2:0]          awprot,
    input  wire [3:0]          awqos,
    input  wire                awvalid,
    output reg                 awready,

    // Write Data Channel (W)
    input  wire [DATA_W-1:0]   wdata,
    input  wire [DATA_W/8-1:0] wstrb,
    input  wire                wlast,
    input  wire                wvalid,
    output reg                 wready,

    // Write Response Channel (B)
    output reg  [ID_W-1:0]     bid,
    output reg  [1:0]          bresp,
    output reg                 bvalid,
    input  wire                bready,

    // Read Address Channel (AR)
    input  wire [ID_W-1:0]     arid,
    input  wire [ADDR_W-1:0]   araddr,
    input  wire [7:0]          arlen,
    input  wire [2:0]          arsize,
    input  wire [1:0]          arburst,
    input  wire                arlock,
    input  wire [3:0]          arcache,
    input  wire [2:0]          arprot,
    input  wire [3:0]          arqos,
    input  wire                arvalid,
    output reg                 arready,

    // Read Data Channel (R)
    output reg  [ID_W-1:0]     rid,
    output reg  [DATA_W-1:0]   rdata,
    output reg  [1:0]          rresp,
    output reg                 rlast,
    output reg                 rvalid,
    input  wire                rready
);

    // -------------------------------------------------------------
    // Internal memory — byte-addressed indexing via (addr >> shift)
    // -------------------------------------------------------------
    localparam ADDR_SHIFT = $clog2(DATA_W/8);
    reg [DATA_W-1:0] mem [0:MEM_DEPTH-1];

    integer idx;
    initial begin
        for (idx = 0; idx < MEM_DEPTH; idx = idx + 1)
            mem[idx] = 0;
        awready = 0; wready = 0;
        bid = 0; bresp = 0; bvalid = 0;
        arready = 0;
        rid = 0; rdata = 0; rresp = 0; rlast = 0; rvalid = 0;
    end

    // Latched values
    reg [ID_W-1:0]   lat_awid;
    reg [ADDR_W-1:0] lat_awaddr;
    reg [ID_W-1:0]   lat_arid;
    reg [ADDR_W-1:0] lat_araddr;

    // -------------------------------------------------------------
    // WRITE channel state machine
    // -------------------------------------------------------------
    reg [1:0] wr_state;
    localparam W_IDLE = 2'd0, W_DATA = 2'd1, W_RESP = 2'd2;

    integer b;

    always @(posedge clk) begin
        if (!rst_n) begin
            wr_state <= W_IDLE;
            awready  <= 0;
            wready   <= 0;
            bvalid   <= 0;
            bid      <= 0;
            bresp    <= 0;
        end else begin
            case (wr_state)

                // Wait for AW handshake
                W_IDLE: begin
                    bvalid  <= 0;
                    awready <= 1;
                    if (awvalid && awready) begin
                        lat_awid   <= awid;
                        lat_awaddr <= awaddr;
                        awready    <= 0;
                        wready     <= 1;
                        wr_state   <= W_DATA;
                    end
                end

                // Wait for W handshake — write into memory
                W_DATA: begin
                    if (wvalid && wready) begin
                        // Byte-strobed write
                        for (b = 0; b < DATA_W/8; b = b + 1) begin
                            if (wstrb[b])
                                mem[lat_awaddr >> ADDR_SHIFT][b*8 +: 8] <= wdata[b*8 +: 8];
                        end
                        wready   <= 0;
                        wr_state <= W_RESP;
                    end
                end

                // Send B response
                W_RESP: begin
                    bvalid <= 1;
                    bid    <= lat_awid;
                    bresp  <= 2'b00;        // OKAY
                    if (bvalid && bready) begin
                        bvalid   <= 0;
                        wr_state <= W_IDLE;
                    end
                end

                default: wr_state <= W_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------
    // READ channel state machine
    // -------------------------------------------------------------
    reg [1:0] rd_state;
    localparam R_IDLE = 2'd0, R_DATA = 2'd1;

    always @(posedge clk) begin
        if (!rst_n) begin
            rd_state <= R_IDLE;
            arready  <= 0;
            rvalid   <= 0;
            rid      <= 0;
            rdata    <= 0;
            rresp    <= 0;
            rlast    <= 0;
        end else begin
            case (rd_state)

                // Wait for AR handshake
                R_IDLE: begin
                    rvalid  <= 0;
                    rlast   <= 0;
                    arready <= 1;
                    if (arvalid && arready) begin
                        lat_arid   <= arid;
                        lat_araddr <= araddr;
                        arready    <= 0;
                        rd_state   <= R_DATA;
                    end
                end

                // Return data — single beat so rlast = 1
                R_DATA: begin
                    rvalid <= 1;
                    rid    <= lat_arid;
                    rdata  <= mem[lat_araddr >> ADDR_SHIFT];
                    rresp  <= 2'b00;        // OKAY
                    rlast  <= 1;
                    if (rvalid && rready) begin
                        rvalid   <= 0;
                        rlast    <= 0;
                        rd_state <= R_IDLE;
                    end
                end

                default: rd_state <= R_IDLE;
            endcase
        end
    end

endmodule
