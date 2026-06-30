// Copyright 2017 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the “License”); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

`ifndef AXI_BUS_SV
`define AXI_BUS_SV

`include "config.sv"

////////////////////////////////////////////////////////////////////////////////
//          Only general functions and definitions are defined here           //
//              These functions are not intended to be modified               //
////////////////////////////////////////////////////////////////////////////////

`define OKAY   2'b00

`define AXI_DEGENERATE_MASTER(m) \
   assign m.aw_id     = 'b0; \
   assign m.aw_addr   = 'b0; \
   assign m.aw_len    = 'b0; \
   assign m.aw_size   = 'b0; \
   assign m.aw_burst  = 'b0; \
   assign m.aw_lock   = 'b0; \
   assign m.aw_cache  = 'b0; \
   assign m.aw_prot   = 'b0; \
   assign m.aw_region = 'b0; \
   assign m.aw_user   = 'b0; \
   assign m.aw_qos    = 'b0; \
   assign m.aw_valid  = 'b0; \
   // m.aw_ready ?? ; \
   assign m.ar_id     = 'b0; \
   assign m.ar_addr   = 'b0; \
   assign m.ar_len    = 'b0; \
   assign m.ar_size   = 'b0; \
   assign m.ar_burst  = 'b0; \
   assign m.ar_lock   = 'b0; \
   assign m.ar_cache  = 'b0; \
   assign m.ar_prot   = 'b0; \
   assign m.ar_region = 'b0; \
   assign m.ar_user   = 'b0; \
   assign m.ar_qos    = 'b0; \
   assign m.ar_valid  = 'b0; \
   // m.ar_ready ?? ; \
   assign m.w_data    = 'b0; \
   assign m.w_strb    = 'b0; \
   assign m.w_last    = 'b0; \
   assign m.w_user    = 'b0; \
   assign m.w_valid   = 'b0; \
   // m.w_ready  ?? ; \
   // m.b_id     ?? ; \
   // m.b_resp   ?? ; \
   // m.b_valid  ?? ; \
   // m.b_user   ?? ; \
   assign m.b_ready   = 'b0; \
   // m.r_id    ??  ; \
   // m.r_data  ??  ; \
   // m.r_resp  ??  ; \
   // m.r_last  ??  ; \
   // m.r_user  ??  ; \
   // m.r_valid ??  ; \
   assign m.r_ready   = 'b0;

`define AXI_DEGENERATE_SLAVE(s) \
   assign s.aw_ready = 'h0 ; \
   assign s.ar_ready = 'h0 ; \
   assign s.w_ready  = 'h0 ; \
   assign s.b_id     = 'h0 ; \
   assign s.b_resp   = 'h0 ; \
   assign s.b_valid  = 'h0 ; \
   assign s.b_user   = 'h0 ; \
   assign s.r_id     = 'h0 ; \
   assign s.r_data   = 'h0 ; \
   assign s.r_resp   = 'h0 ; \
   assign s.r_last   = 'h0 ; \
   assign s.r_user   = 'h0 ; \
   assign s.r_valid  = 'h0 ; 



`define AXI_ASSIGN_SLAVE(lhs, rhs)      \
  assign lhs.aw_addr	  = rhs.aw_addr;	 \
  assign lhs.aw_prot	  = rhs.aw_prot;	 \
  assign lhs.aw_region = rhs.aw_region; \
  assign lhs.aw_len	  = rhs.aw_len;	 \
  assign lhs.aw_size	  = rhs.aw_size;	 \
  assign lhs.aw_burst  = rhs.aw_burst;	 \
  assign lhs.aw_lock	  = rhs.aw_lock;	 \
  assign lhs.aw_cache  = rhs.aw_cache;	 \
  assign lhs.aw_qos	  = rhs.aw_qos;	 \
  assign lhs.aw_id	  = rhs.aw_id;		 \
  assign lhs.aw_user	  = rhs.aw_user;	 \
  assign lhs.aw_valid  = rhs.aw_valid;	 \
  assign rhs.aw_ready  = lhs.aw_ready;	 \
  assign lhs.ar_addr	  = rhs.ar_addr;	 \
  assign lhs.ar_prot	  = rhs.ar_prot;	 \
  assign lhs.ar_region = rhs.ar_region; \
  assign lhs.ar_len	  = rhs.ar_len;	 \
  assign lhs.ar_size	  = rhs.ar_size;	 \
  assign lhs.ar_burst  = rhs.ar_burst;	 \
  assign lhs.ar_lock	  = rhs.ar_lock;	 \
  assign lhs.ar_cache  = rhs.ar_cache;	 \
  assign lhs.ar_qos	  = rhs.ar_qos;	 \
  assign lhs.ar_id	  = rhs.ar_id;		 \
  assign lhs.ar_user	  = rhs.ar_user;	 \
  assign lhs.ar_valid  = rhs.ar_valid;	 \
  assign rhs.ar_ready  = lhs.ar_ready;	 \
  assign lhs.w_valid	  = rhs.w_valid;	 \
  assign lhs.w_data	  = rhs.w_data;	 \
  assign lhs.w_strb	  = rhs.w_strb;	 \
  assign lhs.w_user	  = rhs.w_user;	 \
  assign lhs.w_last	  = rhs.w_last;	 \
  assign rhs.w_ready	  = lhs.w_ready;	 \
  assign rhs.r_data	  = lhs.r_data;	 \
  assign rhs.r_resp	  = lhs.r_resp;	 \
  assign rhs.r_last	  = lhs.r_last;	 \
  assign rhs.r_id		  = lhs.r_id;      \
  assign rhs.r_user	  = lhs.r_user;	 \
  assign rhs.r_valid	  = lhs.r_valid;	 \
  assign lhs.r_ready	  = rhs.r_ready;	 \
  assign rhs.b_resp	  = lhs.b_resp;	 \
  assign rhs.b_id		  = lhs.b_id;      \
  assign rhs.b_user	  = lhs.b_user;	 \
  assign rhs.b_valid	  = lhs.b_valid;	 \
  assign lhs.b_ready	  = rhs.b_ready;

`define AXI_ASSIGN_MASTER(lhs, rhs) `AXI_ASSIGN_SLAVE(rhs, lhs)

interface AXI_BUS
#(
    parameter AXI_ADDR_WIDTH = 32,
    parameter AXI_DATA_WIDTH = 64,
    parameter AXI_ID_WIDTH   = 10,
    parameter AXI_USER_WIDTH = 6
);

  localparam AXI_STRB_WIDTH = AXI_DATA_WIDTH/8;

  logic [AXI_ADDR_WIDTH-1:0] aw_addr;
  logic [2:0]                aw_prot;
  logic [3:0]                aw_region;
  logic [7:0]                aw_len;
  logic [2:0]                aw_size;
  logic [1:0]                aw_burst;
  logic                      aw_lock;
  logic [3:0]                aw_cache;
  logic [3:0]                aw_qos;
  logic [AXI_ID_WIDTH-1:0]   aw_id;
  logic [AXI_USER_WIDTH-1:0] aw_user;
  logic                      aw_ready;
  logic                      aw_valid;

  logic [AXI_ADDR_WIDTH-1:0] ar_addr;
  logic [2:0]                ar_prot;
  logic [3:0]                ar_region;
  logic [7:0]                ar_len;
  logic [2:0]                ar_size;
  logic [1:0]                ar_burst;
  logic                      ar_lock;
  logic [3:0]                ar_cache;
  logic [3:0]                ar_qos;
  logic [AXI_ID_WIDTH-1:0]   ar_id;
  logic [AXI_USER_WIDTH-1:0] ar_user;
  logic                      ar_ready;
  logic                      ar_valid;

  logic                      w_valid;
  logic [AXI_DATA_WIDTH-1:0] w_data;
  logic [AXI_STRB_WIDTH-1:0] w_strb;
  logic [AXI_USER_WIDTH-1:0] w_user;
  logic                      w_last;
  logic                      w_ready;

  logic [AXI_DATA_WIDTH-1:0] r_data;
  logic [1:0]                r_resp;
  logic                      r_last;
  logic [AXI_ID_WIDTH-1:0]   r_id;
  logic [AXI_USER_WIDTH-1:0] r_user;
  logic                      r_ready;
  logic                      r_valid;

  logic [1:0]                b_resp;
  logic [AXI_ID_WIDTH-1:0]   b_id;
  logic [AXI_USER_WIDTH-1:0] b_user;
  logic                      b_ready;
  logic                      b_valid;

  // Master Side
  //***************************************
  modport Master
  (

    output aw_valid, output aw_addr, output aw_prot, output aw_region,
    output aw_len, output aw_size, output aw_burst, output aw_lock,
    output aw_cache, output aw_qos, output aw_id, output aw_user,
    input aw_ready,

    output ar_valid, output ar_addr, output ar_prot, output ar_region,
    output ar_len, output ar_size, output ar_burst, output ar_lock,
    output ar_cache, output ar_qos, output ar_id, output ar_user,
    input ar_ready,

    output w_valid, output w_data, output w_strb,  output w_user, output w_last,
    input w_ready,

    input r_valid, input r_data, input r_resp, input r_last, input r_id, input r_user,
    output r_ready,

    input b_valid, input b_resp, input b_id, input b_user,
    output b_ready

  );

  // Slave Side
  //***************************************
  modport Slave
  (

    input aw_valid, input aw_addr, input aw_prot, input aw_region,
    input aw_len, input aw_size, input aw_burst, input aw_lock,
    input aw_cache, input aw_qos, input aw_id, input aw_user,
    output aw_ready,

    input ar_valid, input ar_addr, input ar_prot, input ar_region,
    input ar_len, input ar_size, input ar_burst, input ar_lock,
    input ar_cache, input ar_qos, input ar_id, input ar_user,
    output ar_ready,

    input w_valid, input w_data, input w_strb, input w_user, input w_last,
    output w_ready,

    output r_valid, output r_data, output r_resp, output r_last, output r_id, output r_user,
    input r_ready,

    output b_valid, output b_resp, output b_id, output b_user,
    input b_ready

  );

endinterface

`endif
