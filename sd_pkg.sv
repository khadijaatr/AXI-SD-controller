
//=========================================================================
// sd_pkg.sv : shared constants for the SD BFM
//   Compile this FIRST so the other files can use these names.
//=========================================================================
package sd_pkg;

  // Block size and how many blocks the card stores.
  // (Real SD blocks are 512 bytes; we use 16 so you can print and read them.)
  localparam int BLOCK_BYTES = 16;
  localparam int NUM_BLOCKS  = 8;

  // The three commands this model understands.
  localparam int CMD0_RESET  = 0;    // reset the card
  localparam int CMD24_WRITE = 24;   // write one block
  localparam int CMD17_READ  = 17;   // read one block

endpackage : sd_pkg
