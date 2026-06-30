
//=========================================================================
// sd_if.sv : the SD bus, modelled as a SystemVerilog interface.
//
//   Holds the clock and the two shared, bidirectional lines (cmd, dat) plus
//   each side's drive signals (output-enable + value).  The line resolution
//   lives here: whichever side asserts its enable drives the line; when no
//   one drives, the tri1 net floats high (idle).  Two modports give the host
//   and the card the correct direction on each signal.
//=========================================================================
interface sd_if;
  logic clk;          // bus clock (driven by the testbench)
  tri1  cmd;          // command/response line, idles high
  tri1  dat;          // data line, idles high

  // host's drive of each line (output-enable + value)
  logic host_cmd_oe, host_cmd_val, host_dat_oe, host_dat_val;
  // card's drive of each line
  logic card_cmd_oe, card_cmd_val, card_dat_oe, card_dat_val;

  // Resolution: the enabled side drives; otherwise the line floats high (tri1).
  assign cmd = host_cmd_oe ? host_cmd_val : (card_cmd_oe ? card_cmd_val : 1'bz);
  assign dat = host_dat_oe ? host_dat_val : (card_dat_oe ? card_dat_val : 1'bz);

  modport host (input  clk, input cmd, input dat,
                output host_cmd_oe, output host_cmd_val,
                output host_dat_oe, output host_dat_val);

  modport card (input  clk, input cmd, input dat,
                output card_cmd_oe, output card_cmd_val,
                output card_dat_oe, output card_dat_val);
endinterface
