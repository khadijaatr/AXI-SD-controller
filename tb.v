
// =============================================================
//  Testbench — AXI4 Full BFM Demo
//  Connects master and slave directly
//  All checks live in this file
// =============================================================
module tb;

    // ---- Bus parameters ----
    localparam DATA_W = 32;
    localparam ADDR_W = 32;
    localparam ID_W   = 4;
    localparam STRB_W = DATA_W/8;

    // ---- Clock & reset ----
    reg clk   = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    // ---- AXI4 wires ----
    wire [ID_W-1:0]    awid;
    wire [ADDR_W-1:0]  awaddr;
    wire [7:0]         awlen;
    wire [2:0]         awsize;
    wire [1:0]         awburst;
    wire               awlock;
    wire [3:0]         awcache;
    wire [2:0]         awprot;
    wire [3:0]         awqos;
    wire               awvalid;
    wire               awready;

    wire [DATA_W-1:0]  wdata;
    wire [STRB_W-1:0]  wstrb;
    wire               wlast;
    wire               wvalid;
    wire               wready;

    wire [ID_W-1:0]    bid;
    wire [1:0]         bresp;
    wire               bvalid;
    wire               bready;

    wire [ID_W-1:0]    arid;
    wire [ADDR_W-1:0]  araddr;
    wire [7:0]         arlen;
    wire [2:0]         arsize;
    wire [1:0]         arburst;
    wire               arlock;
    wire [3:0]         arcache;
    wire [2:0]         arprot;
    wire [3:0]         arqos;
    wire               arvalid;
    wire               arready;

    wire [ID_W-1:0]    rid;
    wire [DATA_W-1:0]  rdata;
    wire [1:0]         rresp;
    wire               rlast;
    wire               rvalid;
    wire               rready;

    // ---- Master BFM ----
    axi4_master_bfm #(.DATA_W(DATA_W), .ADDR_W(ADDR_W), .ID_W(ID_W)) master (
        .clk(clk), .rst_n(rst_n),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
        .awburst(awburst), .awlock(awlock), .awcache(awcache),
        .awprot(awprot), .awqos(awqos), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
        .wvalid(wvalid), .wready(wready),
        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize),
        .arburst(arburst), .arlock(arlock), .arcache(arcache),
        .arprot(arprot), .arqos(arqos), .arvalid(arvalid), .arready(arready),
        .rid(rid), .rdata(rdata), .rresp(rresp),
        .rlast(rlast), .rvalid(rvalid), .rready(rready)
    );

    // ---- Slave BFM ----
    axi4_slave_bfm #(.DATA_W(DATA_W), .ADDR_W(ADDR_W), .ID_W(ID_W), .MEM_DEPTH(256)) slave (
        .clk(clk), .rst_n(rst_n),
        .awid(awid), .awaddr(awaddr), .awlen(awlen), .awsize(awsize),
        .awburst(awburst), .awlock(awlock), .awcache(awcache),
        .awprot(awprot), .awqos(awqos), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wlast(wlast),
        .wvalid(wvalid), .wready(wready),
        .bid(bid), .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .arid(arid), .araddr(araddr), .arlen(arlen), .arsize(arsize),
        .arburst(arburst), .arlock(arlock), .arcache(arcache),
        .arprot(arprot), .arqos(arqos), .arvalid(arvalid), .arready(arready),
        .rid(rid), .rdata(rdata), .rresp(rresp),
        .rlast(rlast), .rvalid(rvalid), .rready(rready)
    );

    // ---- Scoreboard ----
    integer pass_count = 0;
    integer fail_count = 0;

    task check;
        input [ADDR_W-1:0] addr;
        input [DATA_W-1:0] expected;
        input [DATA_W-1:0] got;
        begin
            if (got === expected) begin
                $display("[PASS] addr=0x%08h  exp=0x%08h  got=0x%08h", addr, expected, got);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] addr=0x%08h  exp=0x%08h  got=0x%08h", addr, expected, got);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ---- Watchdog ----
    initial begin
        #50000;
        $display("[WATCHDOG] Timeout!");
        $finish;
    end

    // ---- Tests ----
    reg [DATA_W-1:0] rd_data;
    reg [1:0]        rd_resp;
    integer i;

    initial begin
        $dumpfile("axi4.vcd");
        $dumpvars(0, tb.master);
        $dumpvars(0, tb.slave);

        rst_n = 0;
        repeat(5) @(posedge clk);
        rst_n = 1;
        repeat(3) @(posedge clk);

        $display("====================================");
        $display("   AXI4 Full BFM  -  Test Start");
        $display("====================================");

        // Test 1: write then read
        $display("\n--- Test 1: Write then Read ---");
        master.write(4'h1, 32'h00000000, 32'hDEADBEEF, 4'hF);
        master.read (4'h1, 32'h00000000, rd_data, rd_resp);
        check(32'h00000000, 32'hDEADBEEF, rd_data);

        // Test 2: multiple addresses
        $display("\n--- Test 2: Multiple addresses ---");
        master.write(4'h2, 32'h00000004, 32'h12345678, 4'hF);
        master.write(4'h3, 32'h00000008, 32'hCAFEBABE, 4'hF);
        master.write(4'h4, 32'h0000000C, 32'hFFFF0000, 4'hF);
        master.read(4'h2, 32'h00000004, rd_data, rd_resp);
        check(32'h00000004, 32'h12345678, rd_data);
        master.read(4'h3, 32'h00000008, rd_data, rd_resp);
        check(32'h00000008, 32'hCAFEBABE, rd_data);
        master.read(4'h4, 32'h0000000C, rd_data, rd_resp);
        check(32'h0000000C, 32'hFFFF0000, rd_data);

        // Test 3: overwrite
        $display("\n--- Test 3: Overwrite ---");
        master.write(4'h5, 32'h00000000, 32'h11111111, 4'hF);
        master.write(4'h5, 32'h00000000, 32'h22222222, 4'hF);
        master.read (4'h5, 32'h00000000, rd_data, rd_resp);
        check(32'h00000000, 32'h22222222, rd_data);

        // Test 5: sequential
        $display("\n--- Test 5: Sequential 4 writes/reads ---");
        for (i = 0; i < 4; i = i + 1)
            master.write(4'h7, 32'h00000020 + (i*4), 32'hA0000000 + i, 4'hF);
        for (i = 0; i < 4; i = i + 1) begin
            master.read(4'h7, 32'h00000020 + (i*4), rd_data, rd_resp);
            check(32'h00000020 + (i*4), 32'hA0000000 + i, rd_data);
        end

        $display("\n====================================");
        $display("   PASS: %0d   FAIL: %0d", pass_count, fail_count);
        $display("====================================");

        $finish;
    end

endmodule
