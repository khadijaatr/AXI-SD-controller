//=========================================================================
// sd_host.sv : the SD HOST (master)
//
//   It reads the two shared lines through bus.cmd / bus.dat, and drives them
//   through its own enable+value outputs (bus.host_cmd_oe/bus.host_cmd_val, bus.host_dat_oe/bus.host_dat_val).
//   The testbench wires these to the card and resolves who is driving.
//
//   Timing rule: SENDER changes its line on the FALLING clock edge;
//                RECEIVER reads the line on the RISING clock edge.
//=========================================================================
module sd_host (sd_if.host bus);
  import sd_pkg::*;

  // Buffers: the testbench fills host_wbuf before a write and reads host_rbuf
  // after a read.
  reg [7:0] host_wbuf [0:BLOCK_BYTES-1];
  reg [7:0] host_rbuf [0:BLOCK_BYTES-1];

  initial begin bus.host_cmd_oe = 0; bus.host_cmd_val = 1; bus.host_dat_oe = 0; bus.host_dat_val = 1; end

  //----------------------------------------------------------------------
  // Send a command = start(0) + 6-bit number + 32-bit argument + stop(1).
  // (A real SD command also ends with a 7-bit CRC; left out for clarity.)
  //----------------------------------------------------------------------
  task automatic send_command(input [5:0] number, input [31:0] arg);
	reg [39:0] frame; integer i;
	begin
	  frame = {1'b0, number, arg, 1'b1};
	  bus.host_cmd_oe = 1;
	  for (i = 39; i >= 0; i = i - 1) begin
		@(negedge bus.clk); bus.host_cmd_val = frame[i];   // most-significant bit first
	  end
	  @(negedge bus.clk);
	  bus.host_cmd_oe = 0; bus.host_cmd_val = 1;                 // let go so the card can answer
	  $display("[%0t] HOST: sent CMD%0d arg=%0d", $time, number, arg);
	end
  endtask

  // Read the card's reply = start(0) + 6-bit number + 8-bit status + stop(1).
  task automatic read_response(output [5:0] number, output [7:0] status);
	integer i;
	begin
	  @(posedge bus.clk);
	  while (bus.cmd !== 1'b0) @(posedge bus.clk);  // wait for start bit (line low)
	  for (i = 5; i >= 0; i = i - 1) begin @(posedge bus.clk); number[i] = bus.cmd; end
	  for (i = 7; i >= 0; i = i - 1) begin @(posedge bus.clk); status[i] = bus.cmd; end
	  @(posedge bus.clk);                          // stop bit
	  $display("[%0t] HOST: got reply for CMD%0d (status=%0d)", $time, number, status);
	end
  endtask

  // Send a data block = start(0) + all the bytes + stop(1).
  // (A real SD card adds a 16-bit CRC after the data; left out here.)
  task automatic send_data;
	integer b, k;
	begin
	  repeat (2) @(negedge bus.clk);               // small gap so the card is listening
	  bus.host_dat_oe = 1;
	  @(negedge bus.clk); bus.host_dat_val = 0;             // start bit
	  for (b = 0; b < BLOCK_BYTES; b = b + 1)
		for (k = 7; k >= 0; k = k - 1) begin
		  @(negedge bus.clk); bus.host_dat_val = host_wbuf[b][k];
		end
	  @(negedge bus.clk); bus.host_dat_val = 1;             // stop bit
	  @(negedge bus.clk); bus.host_dat_oe = 0;              // let go of the line
	end
  endtask

  // Receive a data block from the card into host_rbuf.
  task automatic recv_data;
	integer b, k;
	begin
	  @(posedge bus.clk);
	  while (bus.dat !== 1'b0) @(posedge bus.clk);  // wait for start bit
	  for (b = 0; b < BLOCK_BYTES; b = b + 1)
		for (k = 7; k >= 0; k = k - 1) begin @(posedge bus.clk); host_rbuf[b][k] = bus.dat; end
	  @(posedge bus.clk);                          // stop bit
	end
  endtask

  //----------------------------------------------------------------------
  // The two operations a user actually calls:
  //----------------------------------------------------------------------
  task automatic write_block(input [31:0] blknum);
	reg [5:0] n; reg [7:0] s;
	begin
	  send_command(CMD24_WRITE, blknum);
	  read_response(n, s);
	  send_data;
	end
  endtask

  task automatic read_block(input [31:0] blknum);
	reg [5:0] n; reg [7:0] s;
	begin
	  send_command(CMD17_READ, blknum);
	  read_response(n, s);
	  recv_data;
	end
  endtask

endmodule : sd_host
