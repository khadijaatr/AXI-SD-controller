//=========================================================================
// axi_sdio_tb.sv
//
// Testbench for axi_sdio_controller using:
//   - provided AXI4 master BFM
//   - provided sd_if
//   - provided sd_card BFM
//=========================================================================

module axi_sdio_tb;
  import sd_pkg::*;

  localparam int DATA_W = 32;
  localparam int ADDR_W = 32;
  localparam int ID_W   = 4;
  localparam int USER_W = 1;

  localparam [31:0] REG_CTRL       = 32'h0000_0000;
  localparam [31:0] REG_STATUS     = 32'h0000_0004;
  localparam [31:0] REG_BLOCK_ADDR = 32'h0000_0008;
  localparam [31:0] REG_DATA       = 32'h0000_0010;

  localparam [31:0] CTRL_START     = 32'h0000_0001;
  localparam [31:0] CTRL_WRITE     = 32'h0000_0002;
  localparam [31:0] CTRL_RESET     = 32'h0000_0004;

  logic rst_n;

  sd_if sd_bus();
  initial sd_bus.clk = 1'b0;
  always #20 sd_bus.clk = ~sd_bus.clk; // 25 MHz

  AXI_BUS #(
	.AXI_ADDR_WIDTH(ADDR_W),
	.AXI_DATA_WIDTH(DATA_W),
	.AXI_ID_WIDTH(ID_W),
	.AXI_USER_WIDTH(USER_W)
  ) axi();

  axi_sdio_controller #(
	.AXI_ADDR_WIDTH(ADDR_W),
	.AXI_DATA_WIDTH(DATA_W),
	.AXI_ID_WIDTH(ID_W),
	.AXI_USER_WIDTH(USER_W),
	.TIMEOUT_CYCLES(2000)
  ) dut (
	.clk   (sd_bus.clk),
	.rst_n (rst_n),
	.axi   (axi.Slave),
	.sd    (sd_bus.host)
  );

  sd_card u_card (sd_bus.card);

  axi4_master_bfm #(
	.DATA_W(DATA_W),
	.ADDR_W(ADDR_W),
	.ID_W(ID_W)
  ) master (
	.clk     (sd_bus.clk),
	.rst_n   (rst_n),

	.awid    (axi.aw_id),
	.awaddr  (axi.aw_addr),
	.awlen   (axi.aw_len),
	.awsize  (axi.aw_size),
	.awburst (axi.aw_burst),
	.awlock  (axi.aw_lock),
	.awcache (axi.aw_cache),
	.awprot  (axi.aw_prot),
	.awqos   (axi.aw_qos),
	.awvalid (axi.aw_valid),
	.awready (axi.aw_ready),

	.wdata   (axi.w_data),
	.wstrb   (axi.w_strb),
	.wlast   (axi.w_last),
	.wvalid  (axi.w_valid),
	.wready  (axi.w_ready),

	.bid     (axi.b_id),
	.bresp   (axi.b_resp),
	.bvalid  (axi.b_valid),
	.bready  (axi.b_ready),

	.arid    (axi.ar_id),
	.araddr  (axi.ar_addr),
	.arlen   (axi.ar_len),
	.arsize  (axi.ar_size),
	.arburst (axi.ar_burst),
	.arlock  (axi.ar_lock),
	.arcache (axi.ar_cache),
	.arprot  (axi.ar_prot),
	.arqos   (axi.ar_qos),
	.arvalid (axi.ar_valid),
	.arready (axi.ar_ready),

	.rid     (axi.r_id),
	.rdata   (axi.r_data),
	.rresp   (axi.r_resp),
	.rlast   (axi.r_last),
	.rvalid  (axi.r_valid),
	.rready  (axi.r_ready)
  );

  // AXI_BUS has signals that the flat master BFM does not use.
  assign axi.aw_region = '0;
  assign axi.aw_user   = '0;
  assign axi.ar_region = '0;
  assign axi.ar_user   = '0;
  assign axi.w_user    = '0;

  task automatic axi_write32(input [31:0] addr, input [31:0] data);
	begin
	  master.write(4'h1, addr, data, 4'hF);
	end
  endtask

  task automatic axi_read32(input [31:0] addr, output [31:0] data);
	logic [1:0] resp;
	begin
	  master.read(4'h2, addr, data, resp);
	  if (resp != 2'b00) $error("AXI read error at addr 0x%08h, resp=%0d", addr, resp);
	end
  endtask

  task automatic wait_done(output [31:0] status);
	begin
	  status = 32'd0;
	  repeat (5000) begin
		axi_read32(REG_STATUS, status);
		if (status[1] || status[2] || status[3]) begin
		  disable wait_done;
		end
		@(posedge sd_bus.clk);
	  end
	  $error("Timeout while polling controller STATUS");
	end
  endtask

  integer i;
  integer errors;
  logic [31:0] status;
  logic [31:0] rd_word;
  logic [7:0]  expected [0:BLOCK_BYTES-1];
  logic [7:0]  actual   [0:BLOCK_BYTES-1];

  initial begin
	$dumpfile("axi_sdio_tb.vcd");
	$dumpvars(0, axi_sdio_tb);

	rst_n = 1'b0;
	repeat (5) @(posedge sd_bus.clk);
	rst_n = 1'b1;
	repeat (5) @(posedge sd_bus.clk);

	// Optional card reset: CTRL = START | RESET
	axi_write32(REG_CTRL, CTRL_START | CTRL_RESET);
	wait_done(status);
	$display("RESET done, STATUS = 0x%08h", status);

	// Build 16-byte pattern: 0x10, 0x11, ..., 0x1F
	for (i = 0; i < BLOCK_BYTES; i++) begin
	  expected[i] = 8'h10 + i[7:0];
	end

	// Write DATA buffer through AXI, four bytes per 32-bit word.
	for (i = 0; i < BLOCK_BYTES; i = i + 4) begin
	  axi_write32(REG_DATA + i,
				  {expected[i+3], expected[i+2], expected[i+1], expected[i+0]});
	end

	// Write block 2 to the SD card.
	axi_write32(REG_BLOCK_ADDR, 32'd2);
	axi_write32(REG_CTRL, CTRL_START | CTRL_WRITE);
	wait_done(status);
	$display("WRITE done, STATUS = 0x%08h", status);
	if (status[2] || status[3]) $fatal(1, "Controller reported write error");

	// Clear local DATA buffer by overwriting it with zero through AXI.
	for (i = 0; i < BLOCK_BYTES; i = i + 4) begin
	  axi_write32(REG_DATA + i, 32'h0000_0000);
	end

	// Read block 2 from the SD card.
	axi_write32(REG_BLOCK_ADDR, 32'd2);
	axi_write32(REG_CTRL, CTRL_START); // read: WRITE_NREAD=0
	wait_done(status);
	$display("READ done, STATUS = 0x%08h", status);
	if (status[2] || status[3]) $fatal(1, "Controller reported read error");

	// Read DATA buffer back through AXI.
	for (i = 0; i < BLOCK_BYTES; i = i + 4) begin
	  axi_read32(REG_DATA + i, rd_word);
	  actual[i+0] = rd_word[7:0];
	  actual[i+1] = rd_word[15:8];
	  actual[i+2] = rd_word[23:16];
	  actual[i+3] = rd_word[31:24];
	end

	errors = 0;
	$write("\nexpected:");
	for (i = 0; i < BLOCK_BYTES; i++) $write(" %02h", expected[i]);
	$write("\nactual  :");
	for (i = 0; i < BLOCK_BYTES; i++) $write(" %02h", actual[i]);
	$display("");

	for (i = 0; i < BLOCK_BYTES; i++) begin
	  if (actual[i] !== expected[i]) begin
		errors++;
		$display("Mismatch byte %0d: expected=%02h actual=%02h", i, expected[i], actual[i]);
	  end
	end

	if (errors == 0) $display("\nRESULT: PASS - AXI to SDIO transfer works");
	else             $fatal(1, "RESULT: FAIL - %0d byte(s) differ", errors);

	$finish;
  end

endmodule : axi_sdio_tb
