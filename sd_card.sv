
//=========================================================================
// sd_card.sv : the SD CARD (slave)
//
//   Mirror image of the host: it reads the lines through bus.cmd / bus.dat and
//   drives them through bus.card_cmd_oe/bus.card_cmd_val, bus.card_dat_oe/bus.card_dat_val.  Its "brain" is one
//   forever loop: wait for a command, then react.
//=========================================================================
module sd_card (sd_if.card bus);
  import sd_pkg::*;

  reg [7:0] card_mem [0:NUM_BLOCKS*BLOCK_BYTES-1];   // the card's storage

  integer j;
  initial begin
    bus.card_cmd_oe = 0; bus.card_cmd_val = 1; bus.card_dat_oe = 0; bus.card_dat_val = 1;
    for (j = 0; j < NUM_BLOCKS*BLOCK_BYTES; j = j + 1) card_mem[j] = 8'h00;
  end

  //----------------------------------------------------------------------
  // Receive a command frame from the host.
  //----------------------------------------------------------------------
  task automatic recv_command(output [5:0] number, output [31:0] arg);
    integer i;
    begin
      @(posedge bus.clk);
      while (bus.cmd !== 1'b0) @(posedge bus.clk);  // wait for start bit
      for (i = 5; i >= 0; i = i - 1) begin @(posedge bus.clk); number[i] = bus.cmd; end
      for (i = 31; i >= 0; i = i - 1) begin @(posedge bus.clk); arg[i]   = bus.cmd; end
      @(posedge bus.clk);                          // stop bit
    end
  endtask

  // Send a short reply on the command line.
  task automatic send_response(input [5:0] number, input [7:0] status);
    reg [15:0] frame; integer i;
    begin
      frame = {1'b0, number, status, 1'b1};
      repeat (2) @(negedge bus.clk);               // turnaround gap
      bus.card_cmd_oe = 1;
      for (i = 15; i >= 0; i = i - 1) begin @(negedge bus.clk); bus.card_cmd_val = frame[i]; end
      @(negedge bus.clk); bus.card_cmd_oe = 0; bus.card_cmd_val = 1;
    end
  endtask

  // Send one stored block to the host.
  task automatic send_data(input [31:0] blknum);
    integer b, k, base;
    begin
      base = blknum * BLOCK_BYTES;
      repeat (2) @(negedge bus.clk);
      bus.card_dat_oe = 1;
      @(negedge bus.clk); bus.card_dat_val = 0;             // start bit
      for (b = 0; b < BLOCK_BYTES; b = b + 1)
        for (k = 7; k >= 0; k = k - 1) begin
          @(negedge bus.clk); bus.card_dat_val = card_mem[base+b][k];
        end
      @(negedge bus.clk); bus.card_dat_val = 1;             // stop bit
      @(negedge bus.clk); bus.card_dat_oe = 0;
    end
  endtask

  // Receive one block from the host and store it.
  task automatic recv_data(input [31:0] blknum);
    integer b, k, base; reg [7:0] one_byte;
    begin
      base = blknum * BLOCK_BYTES;
      @(posedge bus.clk);
      while (bus.dat !== 1'b0) @(posedge bus.clk);  // wait for start bit
      for (b = 0; b < BLOCK_BYTES; b = b + 1) begin
        for (k = 7; k >= 0; k = k - 1) begin @(posedge bus.clk); one_byte[k] = bus.dat; end
        card_mem[base+b] = one_byte;
      end
      @(posedge bus.clk);                          // stop bit
    end
  endtask

  //----------------------------------------------------------------------
  // The card's brain: loop forever and react to each command.
  //----------------------------------------------------------------------
  reg [5:0]  number;
  reg [31:0] arg;
  initial begin
    forever begin
      recv_command(number, arg);
      $display("[%0t] CARD: got CMD%0d arg=%0d", $time, number, arg);
      case (number)
        CMD0_RESET:  ; // a reset: nothing to send back in this model
        CMD24_WRITE: begin
                       send_response(number, 8'd0);   // "ok"
                       recv_data(arg);
                       $display("[%0t] CARD: stored block %0d", $time, arg);
                     end
        CMD17_READ:  begin
                       send_response(number, 8'd0);   // "ok"
                       send_data(arg);
                       $display("[%0t] CARD: sent block %0d", $time, arg);
                     end
        default:     send_response(number, 8'hFF);     // unknown command
      endcase
    end
  end

endmodule : sd_card
