//=========================================================================
// sd_tb.sv : the testbench
//
//   Instantiates the bus interface, drives the clock, connects the host and
//   card to it through their modports, and runs the test: reset, write a
//   pattern, read it back, and check that it matches.
//
//   This version uses a SystemVerilog interface, so it targets a commercial
//   simulator (VCS / Questa / Xcelium).
//=========================================================================
module sd_tb;
  import sd_pkg::*;

  sd_if bus();                        // the shared bus
  initial bus.clk = 0;
  always #20 bus.clk = ~bus.clk;      // 25 MHz

  sd_host u_host (bus);               // connects through the .host modport
  sd_card u_card (bus);               // connects through the .card modport

  integer i, errors;
  initial begin
	$dumpfile("sd_tb.vcd");
	$dumpvars(0, sd_tb);

	u_host.send_command(CMD0_RESET, 0);            // 1) reset the card
	repeat (4) @(negedge bus.clk);

	for (i = 0; i < BLOCK_BYTES; i = i + 1)        // 2) build a pattern...
	  u_host.host_wbuf[i] = 8'h10 + i[7:0];
	u_host.write_block(2);                         //    ...write it to block 2

	u_host.read_block(2);                          // 3) read block 2 back

	errors = 0;                                    // 4) compare
	for (i = 0; i < BLOCK_BYTES; i = i + 1)
	  if (u_host.host_rbuf[i] !== u_host.host_wbuf[i]) errors = errors + 1;

	$write("\nwrote:"); for (i=0;i<BLOCK_BYTES;i=i+1) $write(" %02h", u_host.host_wbuf[i]);
	$write("\nread :"); for (i=0;i<BLOCK_BYTES;i=i+1) $write(" %02h", u_host.host_rbuf[i]);
	$display("");
	if (errors == 0) $display("\nRESULT: PASS - data read back matches data written");
	else             $display("\nRESULT: FAIL - %0d byte(s) differ", errors);
	$finish;
  end
endmodule : sd_tb
