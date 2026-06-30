// =============================================================
//  AXI4 Full Master BFM
//  File    : axi4_master_bfm.v
//  Features: Single write, single read
//  Params  : DATA_W, ADDR_W, ID_W
//
//  Tasks:
//    master.write(id, addr, data, strb)
//    master.read (id, addr, data, resp)
// =============================================================

module axi4_master_bfm #(
    parameter DATA_W = 32,
    parameter ADDR_W = 32,
    parameter ID_W   = 4
)(
    input  wire                clk,
    input  wire                rst_n,

    // Write Address Channel (AW)
    output reg  [ID_W-1:0]     awid,
    output reg  [ADDR_W-1:0]   awaddr,
    output reg  [7:0]          awlen,
    output reg  [2:0]          awsize,
    output reg  [1:0]          awburst,
    output reg                 awlock,
    output reg  [3:0]          awcache,
    output reg  [2:0]          awprot,
    output reg  [3:0]          awqos,
    output reg                 awvalid,
    input  wire                awready,

    // Write Data Channel (W)
    output reg  [DATA_W-1:0]   wdata,
    output reg  [DATA_W/8-1:0] wstrb,
    output reg                 wlast,
    output reg                 wvalid,
    input  wire                wready,

    // Write Response Channel (B)
    input  wire [ID_W-1:0]     bid,
    input  wire [1:0]          bresp,
    input  wire                bvalid,
    output reg                 bready,

    // Read Address Channel (AR)
    output reg  [ID_W-1:0]     arid,
    output reg  [ADDR_W-1:0]   araddr,
    output reg  [7:0]          arlen,
    output reg  [2:0]          arsize,
    output reg  [1:0]          arburst,
    output reg                 arlock,
    output reg  [3:0]          arcache,
    output reg  [2:0]          arprot,
    output reg  [3:0]          arqos,
    output reg                 arvalid,
    input  wire                arready,

    // Read Data Channel (R)
    input  wire [ID_W-1:0]     rid,
    input  wire [DATA_W-1:0]   rdata,
    input  wire [1:0]          rresp,
    input  wire                rlast,
    input  wire                rvalid,
    output reg                 rready
);

    // -------------------------------------------------------------
    // Drive all outputs idle at start
    // -------------------------------------------------------------
    initial begin
        awid    = 0;  awaddr  = 0;  awlen  = 0;
        awsize  = $clog2(DATA_W/8);
        awburst = 2'b01;  awlock = 0;
        awcache = 4'b0010; awprot = 0; awqos = 0; awvalid = 0;

        wdata   = 0;  wstrb  = {(DATA_W/8){1'b1}};
        wlast   = 0;  wvalid = 0;

        bready  = 0;

        arid    = 0;  araddr  = 0;  arlen  = 0;
        arsize  = $clog2(DATA_W/8);
        arburst = 2'b01;  arlock = 0;
        arcache = 4'b0010; arprot = 0; arqos = 0; arvalid = 0;

        rready  = 0;
    end

    // -------------------------------------------------------------
    // TASK: write — single beat write
    //   id   : transaction ID
    //   addr : write address
    //   data : data to write
    //   strb : byte strobes (all-ones = full word)
    // -------------------------------------------------------------
    task write;
        input [ID_W-1:0]     id;
        input [ADDR_W-1:0]   addr;
        input [DATA_W-1:0]   data;
        input [DATA_W/8-1:0] strb;
        begin
            // Drive on negedge so signals are stable for next posedge
            @(negedge clk);
            awid    = id;
            awaddr  = addr;
            awlen   = 8'd0;          // single beat
            awsize  = $clog2(DATA_W/8);
            awburst = 2'b01;         // INCR
            awvalid = 1;

            wdata   = data;
            wstrb   = strb;
            wlast   = 1;             // single beat -> last
            wvalid  = 1;

            bready  = 1;

            // Wait for AW handshake
            @(posedge clk);
            while (awready !== 1'b1) @(posedge clk);
            @(negedge clk);
            awvalid = 0;

            // Wait for W handshake
            @(posedge clk);
            while (wready !== 1'b1) @(posedge clk);
            @(negedge clk);
            wvalid = 0;
            wlast  = 0;

            // Wait for B handshake
            @(posedge clk);
            while (bvalid !== 1'b1) @(posedge clk);
            @(negedge clk);
            bready = 0;
        end
    endtask

    // -------------------------------------------------------------
    // TASK: read — single beat read
    //   id   : transaction ID
    //   addr : read address
    //   data : output — returned read data
    //   resp : output — read response code
    // -------------------------------------------------------------
    task read;
        input  [ID_W-1:0]   id;
        input  [ADDR_W-1:0] addr;
        output [DATA_W-1:0] data;
        output [1:0]        resp;
        begin
            @(negedge clk);
            arid    = id;
            araddr  = addr;
            arlen   = 8'd0;
            arsize  = $clog2(DATA_W/8);
            arburst = 2'b01;
            arvalid = 1;
            rready  = 1;

            // Wait for AR handshake
            @(posedge clk);
            while (arready !== 1'b1) @(posedge clk);
            @(negedge clk);
            arvalid = 0;

            // Wait for R handshake
            @(posedge clk);
            while (rvalid !== 1'b1) @(posedge clk);
            data = rdata;
            resp = rresp;
            @(negedge clk);
            rready = 0;
        end
    endtask

endmodule
