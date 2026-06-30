//=========================================================================
// axi_sdio_controller.sv
//
// Simple AXI4 single-beat slave to simplified SD native-bus controller.
//
// This controller is designed to work with the provided sd_if/sd_card BFM:
//   - command frame: start(0) + 6-bit cmd + 32-bit arg + stop(1)
//   - response frame: start(0) + 6-bit cmd + 8-bit status + stop(1)
//   - data frame: start(0) + BLOCK_BYTES bytes, MSB first + stop(1)
//
// It supports CMD17 read-single-block and CMD24 write-single-block.
// CMD0 reset is also supported, but the provided card BFM does not return
// a response for CMD0, so the controller completes reset after sending CMD0.
//
// Register map, byte offsets:
//   0x00 CTRL       W/R: bit0 START, bit1 WRITE_NREAD, bit2 RESET_CARD
//   0x04 STATUS     R  : bit0 BUSY, bit1 DONE, bit2 ERROR, bit3 TIMEOUT,
//                         bits[7:4] FSM state, bits[15:8] SD status,
//                         bits[21:16] echoed response command
//   0x08 BLOCK_ADDR W/R: SD block number
//   0x10 DATA       W/R: BLOCK_BYTES-byte transfer buffer
//
// Typical write block flow:
//   1. AXI write DATA bytes at 0x10..0x10+BLOCK_BYTES-1
//   2. AXI write BLOCK_ADDR at 0x08
//   3. AXI write CTRL = 32'h0000_0003  // START=1, WRITE_NREAD=1
//   4. Poll STATUS.DONE
//
// Typical read block flow:
//   1. AXI write BLOCK_ADDR at 0x08
//   2. AXI write CTRL = 32'h0000_0001  // START=1, WRITE_NREAD=0
//   3. Poll STATUS.DONE
//   4. AXI read DATA bytes at 0x10..0x10+BLOCK_BYTES-1
//=========================================================================

module axi_sdio_controller #(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32,
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_USER_WIDTH = 1,
    parameter int TIMEOUT_CYCLES = 10000
)(
    input  logic clk,
    input  logic rst_n,

    AXI_BUS.Slave axi,
    sd_if.host    sd
);
  import sd_pkg::*;

  localparam int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;

  localparam int REG_CTRL       = 16'h0000;
  localparam int REG_STATUS     = 16'h0004;
  localparam int REG_BLOCK_ADDR = 16'h0008;
  localparam int REG_DATA       = 16'h0010;

  // SD FSM states, kept as simple numeric codes so STATUS[7:4] is useful.
  localparam logic [3:0]
    SD_IDLE       = 4'd0,
    SD_CMD        = 4'd1,
    SD_WAIT_RESP  = 4'd2,
    SD_RESP       = 4'd3,
    SD_WRITE_DATA = 4'd4,
    SD_WAIT_DATA  = 4'd5,
    SD_READ_DATA  = 4'd6,
    SD_READ_STOP  = 4'd7,
    SD_FINISH     = 4'd8;

  // AXI write buffering.  AXI AW and W channels are independent, so we latch
  // them separately and perform the register write when both are present.
  logic aw_hold, w_hold;
  logic [AXI_ADDR_WIDTH-1:0] lat_awaddr;
  logic [AXI_ID_WIDTH-1:0]   lat_awid;
  logic [AXI_DATA_WIDTH-1:0] lat_wdata;
  logic [AXI_STRB_WIDTH-1:0] lat_wstrb;

  // AXI-readable controller registers/state.
  logic [31:0] block_addr;
  logic        req_write;     // 1 = CMD24 write, 0 = CMD17 read
  logic        req_reset;     // 1 = CMD0 reset
  logic [3:0]  start_seq;     // AXI side increments this to request operation
  logic [3:0]  start_seen;    // SD side copies this after accepting operation

  logic        busy;
  logic        done;
  logic        error;
  logic        timeout_error;

  logic [3:0]  sd_state;
  logic [5:0]  cmd_expected;
  logic [5:0]  resp_cmd;
  logic [7:0]  resp_status;

  // One shared transfer buffer.  Before CMD24, software writes it through AXI.
  // After CMD17, the controller fills it and software reads it through AXI.
  logic [7:0] data_buf [0:BLOCK_BYTES-1];

  // SD serial helpers.
  logic [39:0] cmd_shift;
  int unsigned cmd_bit_idx;
  int unsigned resp_bit_idx;
  int unsigned data_bit_idx;
  int unsigned timeout_cnt;

  // ----------------------------------------------------------------------
  // Small utility functions
  // ----------------------------------------------------------------------
  function automatic [31:0] apply_wstrb32(
      input [31:0] old_value,
      input [31:0] new_value,
      input [3:0]  strb
  );
    automatic logic [31:0] result;
    begin
      result = old_value;
      for (int i = 0; i < 4; i++) begin
        if (strb[i]) result[i*8 +: 8] = new_value[i*8 +: 8];
      end
      return result;
    end
  endfunction

  function automatic logic data_tx_bit(input int unsigned idx);
    automatic int unsigned payload_idx;
    automatic int unsigned byte_i;
    automatic int unsigned bit_i;
    begin
      if (idx == 0) begin
        data_tx_bit = 1'b0;                         // start bit
      end else if (idx == (BLOCK_BYTES*8 + 1)) begin
        data_tx_bit = 1'b1;                         // stop bit
      end else begin
        payload_idx = idx - 1;
        byte_i      = payload_idx / 8;
        bit_i       = 7 - (payload_idx % 8);
        data_tx_bit = data_buf[byte_i][bit_i];
      end
    end
  endfunction

  function automatic [31:0] status_word();
    begin
      status_word = {
        10'd0,
        resp_cmd,
        resp_status,
        sd_state,
        timeout_error,
        error,
        done,
        busy
      };
    end
  endfunction

  function automatic [7:0] read_byte(input int unsigned byte_off);
    automatic logic [31:0] ctrl_word;
    automatic logic [31:0] stat_word;
    automatic logic [31:0] blk_word;
    begin
      ctrl_word = {29'd0, req_reset, req_write, 1'b0}; // START reads as 0
      stat_word = status_word();
      blk_word  = block_addr;

      if (byte_off >= REG_CTRL && byte_off < REG_CTRL + 4) begin
        read_byte = ctrl_word[(byte_off-REG_CTRL)*8 +: 8];
      end else if (byte_off >= REG_STATUS && byte_off < REG_STATUS + 4) begin
        read_byte = stat_word[(byte_off-REG_STATUS)*8 +: 8];
      end else if (byte_off >= REG_BLOCK_ADDR && byte_off < REG_BLOCK_ADDR + 4) begin
        read_byte = blk_word[(byte_off-REG_BLOCK_ADDR)*8 +: 8];
      end else if (byte_off >= REG_DATA && byte_off < REG_DATA + BLOCK_BYTES) begin
        read_byte = data_buf[byte_off-REG_DATA];
      end else begin
        read_byte = 8'h00;
      end
    end
  endfunction

  function automatic [AXI_DATA_WIDTH-1:0] make_read_data(
      input [AXI_ADDR_WIDTH-1:0] addr
  );
    automatic logic [AXI_DATA_WIDTH-1:0] result;
    automatic int unsigned byte_off;
    begin
      result = '0;
      for (int i = 0; i < AXI_STRB_WIDTH; i++) begin
        byte_off = addr[15:0] + i;
        result[i*8 +: 8] = read_byte(byte_off);
      end
      return result;
    end
  endfunction

  function automatic [5:0] requested_cmd(
      input logic reset_req,
      input logic write_req
  );
    begin
      if (reset_req)      requested_cmd = CMD0_RESET[5:0];
      else if (write_req) requested_cmd = CMD24_WRITE[5:0];
      else                requested_cmd = CMD17_READ[5:0];
    end
  endfunction

  // ----------------------------------------------------------------------
  // Main sequential logic: AXI slave register bank + SD bit-level FSM
  // ----------------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    int unsigned byte_off;
    int unsigned byte_i;
    int unsigned bit_i;
    int unsigned payload_idx;

    if (!rst_n) begin
      // AXI outputs
      axi.aw_ready <= 1'b0;
      axi.w_ready  <= 1'b0;
      axi.b_valid  <= 1'b0;
      axi.b_resp   <= 2'b00;
      axi.b_id     <= '0;
      axi.b_user   <= '0;

      axi.ar_ready <= 1'b0;
      axi.r_valid  <= 1'b0;
      axi.r_resp   <= 2'b00;
      axi.r_last   <= 1'b0;
      axi.r_id     <= '0;
      axi.r_user   <= '0;
      axi.r_data   <= '0;

      aw_hold      <= 1'b0;
      w_hold       <= 1'b0;
      lat_awaddr   <= '0;
      lat_awid     <= '0;
      lat_wdata    <= '0;
      lat_wstrb    <= '0;

      block_addr   <= 32'd0;
      req_write    <= 1'b0;
      req_reset    <= 1'b0;
      start_seq    <= 4'd0;
      start_seen   <= 4'd0;

      busy          <= 1'b0;
      done          <= 1'b0;
      error         <= 1'b0;
      timeout_error <= 1'b0;

      sd_state      <= SD_IDLE;
      cmd_expected  <= 6'd0;
      resp_cmd      <= 6'd0;
      resp_status   <= 8'd0;
      cmd_shift     <= '1;
      cmd_bit_idx   <= 0;
      resp_bit_idx  <= 0;
      data_bit_idx  <= 0;
      timeout_cnt   <= 0;

      sd.host_cmd_oe  <= 1'b0;
      sd.host_cmd_val <= 1'b1;
      sd.host_dat_oe  <= 1'b0;
      sd.host_dat_val <= 1'b1;

      for (int i = 0; i < BLOCK_BYTES; i++) begin
        data_buf[i] <= 8'h00;
      end
    end else begin
      //-------------------------------------------------------------------
      // AXI write address/data handshake
      //-------------------------------------------------------------------
      axi.aw_ready <= (!aw_hold && !axi.b_valid);
      axi.w_ready  <= (!w_hold  && !axi.b_valid);

      if (axi.aw_valid && axi.aw_ready) begin
        aw_hold    <= 1'b1;
        lat_awaddr <= axi.aw_addr;
        lat_awid   <= axi.aw_id;
      end

      if (axi.w_valid && axi.w_ready) begin
        w_hold    <= 1'b1;
        lat_wdata <= axi.w_data;
        lat_wstrb <= axi.w_strb;
      end

      if (axi.b_valid && axi.b_ready) begin
        axi.b_valid <= 1'b0;
      end

      // Perform the AXI write once both AW and W have arrived.
      if (aw_hold && w_hold && !axi.b_valid) begin
        aw_hold     <= 1'b0;
        w_hold      <= 1'b0;
        axi.b_valid <= 1'b1;
        axi.b_resp  <= 2'b00; // OKAY
        axi.b_id    <= lat_awid;
        axi.b_user  <= '0;

        // Aligned 32-bit control registers.
        unique case (lat_awaddr[15:0])
          REG_CTRL: begin
            if (lat_wstrb[0]) begin
              req_write <= lat_wdata[1];
              req_reset <= lat_wdata[2];
              if (lat_wdata[0] && !busy) begin
                start_seq <= start_seq + 4'd1;
              end
            end
          end

          REG_STATUS: begin
            // Optional software clear: writing 1 to DONE/ERROR/TIMEOUT clears them
            // only when the controller is not busy.
            if (!busy) begin
              if (lat_wdata[1]) done          <= 1'b0;
              if (lat_wdata[2]) error         <= 1'b0;
              if (lat_wdata[3]) timeout_error <= 1'b0;
            end
          end

          REG_BLOCK_ADDR: begin
            block_addr <= apply_wstrb32(block_addr, lat_wdata[31:0], lat_wstrb[3:0]);
          end

          default: begin
            // Byte-addressable transfer buffer.
            for (int lane = 0; lane < AXI_STRB_WIDTH; lane++) begin
              byte_off = lat_awaddr[15:0] + lane;
              if (lat_wstrb[lane] &&
                  byte_off >= REG_DATA &&
                  byte_off <  REG_DATA + BLOCK_BYTES) begin
                data_buf[byte_off - REG_DATA] <= lat_wdata[lane*8 +: 8];
              end
            end
          end
        endcase
      end

      //-------------------------------------------------------------------
      // AXI read handshake, single-beat reads
      //-------------------------------------------------------------------
      axi.ar_ready <= !axi.r_valid;

      if (axi.ar_valid && axi.ar_ready) begin
        axi.r_valid <= 1'b1;
        axi.r_resp  <= 2'b00; // OKAY
        axi.r_last  <= 1'b1;
        axi.r_id    <= axi.ar_id;
        axi.r_user  <= '0;
        axi.r_data  <= make_read_data(axi.ar_addr);
      end else if (axi.r_valid && axi.r_ready) begin
        axi.r_valid <= 1'b0;
        axi.r_last  <= 1'b0;
      end

      //-------------------------------------------------------------------
      // SD controller FSM
      //-------------------------------------------------------------------
      unique case (sd_state)
        SD_IDLE: begin
          sd.host_cmd_oe  <= 1'b0;
          sd.host_cmd_val <= 1'b1;
          sd.host_dat_oe  <= 1'b0;
          sd.host_dat_val <= 1'b1;
          timeout_cnt     <= 0;

          if (start_seq != start_seen) begin
            start_seen    <= start_seq;
            busy          <= 1'b1;
            done          <= 1'b0;
            error         <= 1'b0;
            timeout_error <= 1'b0;
            resp_cmd      <= 6'd0;
            resp_status   <= 8'd0;

            cmd_expected  <= requested_cmd(req_reset, req_write);
            cmd_shift     <= {1'b0, requested_cmd(req_reset, req_write), block_addr, 1'b1};
            cmd_bit_idx   <= 39;

            sd.host_cmd_oe  <= 1'b1;
            sd.host_cmd_val <= 1'b0; // first bit of the command frame: start bit
            sd_state        <= SD_CMD;
          end
        end

        SD_CMD: begin
          if (cmd_bit_idx == 0) begin
            sd.host_cmd_oe  <= 1'b0;
            sd.host_cmd_val <= 1'b1;
            timeout_cnt     <= 0;
            if (req_reset) sd_state <= SD_FINISH;  // provided BFM sends no CMD0 response
            else           sd_state <= SD_WAIT_RESP;
          end else begin
            cmd_bit_idx     <= cmd_bit_idx - 1;
            sd.host_cmd_val <= cmd_shift[cmd_bit_idx - 1];
          end
        end

        SD_WAIT_RESP: begin
          if (sd.cmd == 1'b0) begin
            resp_cmd     <= 6'd0;
            resp_status  <= 8'd0;
            resp_bit_idx <= 0;
            timeout_cnt  <= 0;
            sd_state     <= SD_RESP;
          end else if (timeout_cnt >= TIMEOUT_CYCLES) begin
            timeout_error <= 1'b1;
            error         <= 1'b1;
            sd_state      <= SD_FINISH;
          end else begin
            timeout_cnt <= timeout_cnt + 1;
          end
        end

        SD_RESP: begin
          // After the response start bit, sample: 6-bit command, 8-bit status, stop bit.
          if (resp_bit_idx < 6) begin
            resp_cmd[5-resp_bit_idx] <= sd.cmd;
          end else if (resp_bit_idx < 14) begin
            resp_status[13-resp_bit_idx] <= sd.cmd;
          end

          if (resp_bit_idx == 14) begin
            if ((resp_cmd != cmd_expected) || (resp_status != 8'h00)) begin
              error    <= 1'b1;
              sd_state <= SD_FINISH;
            end else if (req_write) begin
              data_bit_idx    <= 0;
              sd.host_dat_oe  <= 1'b1;
              sd.host_dat_val <= 1'b0; // data start bit
              sd_state        <= SD_WRITE_DATA;
            end else begin
              timeout_cnt <= 0;
              sd_state    <= SD_WAIT_DATA;
            end
          end else begin
            resp_bit_idx <= resp_bit_idx + 1;
          end
        end

        SD_WRITE_DATA: begin
          if (data_bit_idx == (BLOCK_BYTES*8 + 1)) begin
            sd.host_dat_oe  <= 1'b0;
            sd.host_dat_val <= 1'b1;
            sd_state        <= SD_FINISH;
          end else begin
            data_bit_idx    <= data_bit_idx + 1;
            sd.host_dat_val <= data_tx_bit(data_bit_idx + 1);
          end
        end

        SD_WAIT_DATA: begin
          if (sd.dat == 1'b0) begin
            data_bit_idx <= 0;
            timeout_cnt  <= 0;
            sd_state     <= SD_READ_DATA;
          end else if (timeout_cnt >= TIMEOUT_CYCLES) begin
            timeout_error <= 1'b1;
            error         <= 1'b1;
            sd_state      <= SD_FINISH;
          end else begin
            timeout_cnt <= timeout_cnt + 1;
          end
        end

        SD_READ_DATA: begin
          payload_idx = data_bit_idx;
          byte_i      = payload_idx / 8;
          bit_i       = 7 - (payload_idx % 8);
          data_buf[byte_i][bit_i] <= sd.dat;

          if (data_bit_idx == (BLOCK_BYTES*8 - 1)) begin
            sd_state <= SD_READ_STOP;
          end else begin
            data_bit_idx <= data_bit_idx + 1;
          end
        end

        SD_READ_STOP: begin
          if (sd.dat != 1'b1) error <= 1'b1;
          sd_state <= SD_FINISH;
        end

        SD_FINISH: begin
          busy          <= 1'b0;
          done          <= 1'b1;
          sd.host_cmd_oe  <= 1'b0;
          sd.host_cmd_val <= 1'b1;
          sd.host_dat_oe  <= 1'b0;
          sd.host_dat_val <= 1'b1;
          sd_state      <= SD_IDLE;
        end

        default: begin
          error    <= 1'b1;
          sd_state <= SD_FINISH;
        end
      endcase
    end
  end

endmodule : axi_sdio_controller
