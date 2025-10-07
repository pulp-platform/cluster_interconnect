// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author: Diyou Shen ETH Zurich
// Author: Marco Bertuletti ETH Zurich

/// Burst Req Manager:
/// Receives a burst request from NumIn initiators and produces a parallel request
/// to NumIn target banks in a target multi-banked memory with NumOut banks.
/// Collects a parallel response from NumOut banks in a target multi-banked memory
/// and groups them according to the RspGF.

module burst_manager
  import burst_pkg::*;
#(
  parameter int unsigned NumIn  = 32, // number of initiator ports
  parameter int unsigned NumOut = 64, // number of destination ports
  parameter int unsigned AddrWidth  = 32,
  parameter int unsigned DataWidth  = 32,
  parameter int unsigned BeWidth    = DataWidth/8,
  // determines the width of the byte offset in a memory word. normally this can be left at the default vaule,
  // but sometimes it needs to be overridden (e.g. when meta-data is supplied to the memory via the wdata signal).
  parameter int unsigned  ByteOffWidth = $clog2(DataWidth-1)-3,
  // Group Response Extension Grouping Factor for TCDM
  parameter int unsigned  RspGF = 1,
  // Dependant parameters. DO NOT CHANGE!
  parameter int unsigned NumInLog2 = (NumIn == 1) ? 1 : $clog2(NumIn),
  // Burst response type can be overwritten for DataWidth > 32b
  // This can happen when the DataWidth includes transaction metadata
  parameter type burst_resp_t = burst_pkg::burst_gresp_t
) (
  input  logic clk_i,
  input  logic rst_ni,
  /// Xbar side
  input  logic   [NumOut-1:0][NumInLog2-1:0] req_ini_addr_i,
  input  logic   [NumOut-1:0][AddrWidth-1:0] req_tgt_addr_i,
  input  logic   [NumOut-1:0][DataWidth-1:0] req_wdata_i,
  input  logic   [NumOut-1:0]                req_wen_i,
  input  logic   [NumOut-1:0][BeWidth-1:0]   req_be_i,
  input  burst_t [NumOut-1:0]                req_burst_i,
  input  logic   [NumOut-1:0]                req_valid_i,
  output logic   [NumOut-1:0]                req_ready_o,
  //
  output logic         [NumOut-1:0][NumInLog2-1:0] resp_ini_addr_o,
  output logic         [NumOut-1:0][DataWidth-1:0] resp_rdata_o,
  output burst_resp_t  [NumOut-1:0]                resp_burst_o,
  output logic         [NumOut-1:0]                resp_valid_o,
  input  logic         [NumOut-1:0]                resp_ready_i,
  /// Bank side
  output logic [NumOut-1:0][NumInLog2-1:0] req_ini_addr_o,
  output logic [NumOut-1:0][AddrWidth-1:0] req_tgt_addr_o,
  output logic [NumOut-1:0][DataWidth-1:0] req_wdata_o,
  output logic [NumOut-1:0]                req_wen_o,
  output logic [NumOut-1:0][BeWidth-1:0]   req_be_o,
  output logic [NumOut-1:0]                req_valid_o,
  input  logic [NumOut-1:0]                req_ready_i,
  //
  input  logic [NumOut-1:0][NumInLog2-1:0] resp_ini_addr_i,
  input  logic [NumOut-1:0][DataWidth-1:0] resp_rdata_i,
  input  logic [NumOut-1:0]                resp_valid_i,
  output logic [NumOut-1:0]                resp_ready_o
);
  /*************************************************************
   * req_i --+--> arbiter --> fifo --> req generator --> req_o *
   *         \--------------- bypass ------------------> req_o *
   * rsp_o <----- data_grouper <----- rsp_i                    *
   *************************************************************/

  // Include FF module
  `include "common_cells/registers.svh"

  localparam int unsigned NumOutLog2 = (NumOut > 32'd1) ? unsigned'($clog2(NumOut)) : 32'd1;

  /******************
   * Burst Identify *
   ******************/

  typedef struct packed {
    logic   [NumInLog2-1:0] ini_addr;
    logic   [AddrWidth-1:0] tgt_addr;
    logic   [DataWidth-1:0] wdata;
    logic                   wen;
    logic   [BeWidth-1:0]   ben;
    burst_t                 burst;
  } arb_data_t;

  arb_data_t [NumOut-1:0]      prearb_data;
  logic      [NumOut-1:0]      prearb_valid, prearb_ready;
  arb_data_t                   postarb_data;
  logic                        postarb_valid, postarb_ready;
  logic      [NumOutLog2-1:0]  postarb_idx;
  logic      [NumOut-1:0]      ready_mask;
  logic      [NumOut-1:0]      valid_mask;


  always_comb begin
    prearb_data    = '0;
    prearb_valid   = '0;
    valid_mask     = req_valid_i;
    for (int unsigned i = 0; i < NumOut; i++) begin
      if (req_valid_i[i] && req_burst_i[i].isburst) begin
        prearb_data[i].ini_addr = req_ini_addr_i[i];
        prearb_data[i].tgt_addr = req_tgt_addr_i[i];
        prearb_data[i].wdata = req_wdata_i[i];
        prearb_data[i].wen = req_wen_i[i];
        prearb_data[i].ben = req_be_i[i];
        prearb_data[i].burst = req_burst_i[i];
        prearb_valid[i] = 1'b1;
        valid_mask[i] = 1'b0;
      end
    end
  end

  // Send ready for retired bursts
  assign ready_mask = prearb_valid & prearb_ready;

  rr_arb_tree #(
    .NumIn     ( NumOut       ),
    .DataType  ( arb_data_t    ),
    .ExtPrio   ( 1'b0),
    .AxiVldRdy ( 1'b1),
    .LockIn    ( 1'b1)
  ) i_rr_arb_tree (
    .clk_i   ( clk_i           ),
    .rst_ni  ( rst_ni          ),
    .flush_i ( 1'b0            ),
    .rr_i    ( '0              ),
    .req_i   ( prearb_valid    ),
    .gnt_o   ( prearb_ready    ),
    .data_i  ( prearb_data     ),
    .req_o   ( postarb_valid   ),
    .gnt_i   ( postarb_ready   ),
    .data_o  ( postarb_data    ),
    .idx_o   ( postarb_idx     )
  );

  typedef struct packed {
    logic   [NumInLog2-1:0]  ini_addr;
    logic   [AddrWidth-1:0]  tgt_addr;
    logic   [DataWidth-1:0]  wdata;
    logic                    wen;
    logic   [BeWidth-1:0]    ben;
    burst_t                  burst;
    logic   [NumOutLog2-1:0] idx;
  } fifo_data_t;

  fifo_data_t   fifo_data, pre_fifo_data;
  logic         fifo_pop, fifo_empty, fifo_full, fifo_push;

  assign postarb_ready = fifo_full ? 1'b0 : 1'b1;
  assign pre_fifo_data.ini_addr = postarb_data.ini_addr;
  assign pre_fifo_data.tgt_addr = postarb_data.tgt_addr;
  assign pre_fifo_data.wdata = postarb_data.wdata;
  assign pre_fifo_data.wen = postarb_data.wen;
  assign pre_fifo_data.ben = postarb_data.ben;
  assign pre_fifo_data.burst = postarb_data.burst;
  assign pre_fifo_data.idx = postarb_idx;

  // Push when FIFO is not full and data is valid
  assign fifo_push = postarb_valid & (~fifo_full);

  // Fall though FIFO to store bursts
  fifo_v3 #(
    .FALL_THROUGH ( 1'b1            ),
    .DEPTH        ( NumOut          ),
    .dtype        ( fifo_data_t     )
  ) i_fall_though_fifo (
    .clk_i        ( clk_i           ),
    .rst_ni       ( rst_ni          ),
    .flush_i      ( 1'b0            ),
    .testmode_i   ( 1'b0            ),
    .full_o       ( fifo_full       ),
    .empty_o      ( fifo_empty      ),
    .usage_o      ( /*not used */   ),
    .data_i       ( pre_fifo_data   ),
    .push_i       ( fifo_push       ),
    .data_o       ( fifo_data       ),
    .pop_i        ( fifo_pop        )
  );

  /*********************
   * Request Generator *
   *********************/

  typedef enum logic {
    Idle, // idle until burst request comes
    DoBurst // generate parallel requests when ready
  } req_gen_fsm_e;

  // FSM state & signals
  req_gen_fsm_e state_d, state_q;
  fifo_data_t req_d, req_q;
  // Indicates which req inputs are involved in a burst
  logic [NumOut-1:0] burst_mask_d, burst_mask_q;
  // Indicates which resp inputs are involved in a burst
  logic [NumOut-1:0] group_mask_d, group_mask_q;
  // indicates if there is pending req/resp to be picked
  logic pending_req, pending_rsp, allready;

  // Store FSM state and signals
  `FF(state_q, state_d, Idle, clk_i, rst_ni);
  `FF(req_q, req_d, '0, clk_i, rst_ni);
  `FF(burst_mask_q, burst_mask_d, '0, clk_i, rst_ni);
  `FF(group_mask_q, group_mask_d, '0, clk_i, rst_ni);

  // a mask with burst length ones
  assign burst_mask_d = ((1'b1 << fifo_data.burst.blen) - 1'b1) << fifo_data.idx;

  always_comb begin : request_generator

    // FSM defaults
    state_d       = state_q;
    req_d         = req_q;

    // Do not take in next burst for now
    fifo_pop = 1'b0;

    // Bypass all requests by default
    req_wdata_o    = req_wdata_i;
    req_tgt_addr_o = req_tgt_addr_i;
    req_ini_addr_o = req_ini_addr_i;
    req_wen_o      = req_wen_i;
    req_be_o       = req_be_i;

    case (state_q)

      // Idle state, ready to take in burst request
      Idle: begin

        // Let valid requests not in burst pass
        req_valid_o = valid_mask;
        req_ready_o = (valid_mask & req_ready_i) | ready_mask;

        // Check if there is a request on the affected banks
        pending_req = |(req_valid_o & burst_mask_d);
        // Check if there is a response on the affected banks
        pending_rsp = |(resp_valid_o & burst_mask_d);

        // Start pending burst
        if (!fifo_empty && !pending_req && !pending_rsp) begin
          fifo_pop = 1'b1;
          req_d    = fifo_data;
          state_d  = DoBurst;
        end

      end

      DoBurst: begin

        // Let valid requests not in burst pass
        req_valid_o = valid_mask & ~burst_mask_q;
        req_ready_o = ((valid_mask & req_ready_i) & ~burst_mask_q) | ready_mask;

        for (int unsigned i = 0; i < NumOut; i++) begin
          // Overwrite the request on affected banks
          if (burst_mask_q[i]) begin
            req_wdata_o[i]    = req_q.wdata;
            req_tgt_addr_o[i] = i + req_q.tgt_addr - req_q.idx;
            req_ini_addr_o[i] = i + req_q.ini_addr - req_q.idx;
            req_wen_o[i]      = req_q.wen;
            req_be_o[i]       = req_q.ben;
            // Set the valid for burst requests
            req_valid_o[i] = 1'b1;
          end
        end

        state_d = Idle;

      end

      default: state_d = Idle;
    endcase
  end

  /******************
   *   Rsp Handling *
   ******************/

  if (RspGF == 1) begin : gen_grouper_bypass
    // Bypass all responses if no grouping
    assign resp_valid_o = resp_valid_i;
    assign resp_ready_o = resp_ready_i;
    assign resp_rdata_o = resp_rdata_i;
    assign resp_ini_addr_o = resp_ini_addr_i;
    assign resp_burst_o = '0;

  end else begin : gen_grouper

    // Number of groups we will check for grouping rsp
    localparam int unsigned NumGroup = RspGF > 0 ? NumOut >> $clog2(RspGF) : NumOut;

    logic         [NumOut-1:0][NumInLog2-1:0] grouped_resp_ini_addr;
    logic         [NumOut-1:0][DataWidth-1:0] grouped_resp_rdata;
    burst_resp_t  [NumOut-1:0]                grouped_resp_burst;
    logic         [NumOut-1:0]                grouped_resp_valid;
    logic         [NumOut-1:0]                grouped_resp_ready;

    always_comb begin
      // Latch the new ports requested in burst
      for (int i = 0; i < NumGroup; i ++) begin
        // If ready cancel the reservation
        if (resp_valid_o[i*RspGF] && resp_ready_i[i*RspGF]) begin
          group_mask_d[i*RspGF+:RspGF] = '0;
        end else begin
          group_mask_d[i*RspGF+:RspGF] = group_mask_q[i*RspGF+:RspGF];
        end
        // If new burst mark the affected banks
        if (state_q == DoBurst) begin
          group_mask_d[i*RspGF+:RspGF] = group_mask_d[i*RspGF+:RspGF] | burst_mask_q[i*RspGF+:RspGF];
        end
      end
    end

    // Assign input data to grouped response
    always_comb begin
      for (int i = 0; i < NumGroup; i++) begin
        grouped_resp_ini_addr[i*RspGF]           = resp_ini_addr_i[i*RspGF];
        grouped_resp_rdata[i*RspGF]              = resp_rdata_i[i*RspGF];
        grouped_resp_burst[i*RspGF].isburst      = &resp_valid_i[i*RspGF+:RspGF];
        grouped_resp_valid[i*RspGF]              = &resp_valid_i[i*RspGF+:RspGF];
        grouped_resp_ready[i*RspGF]              = resp_valid_o[i*RspGF] && resp_ready_i[i*RspGF];

        for (int j = 1; j < RspGF; j++) begin
          grouped_resp_ini_addr[i*RspGF+j]       = '0;
          grouped_resp_rdata[i*RspGF+j]          = '0;
          grouped_resp_burst[i*RspGF].gdata[j-1] = resp_rdata_i[i*RspGF+j];
          grouped_resp_burst[i*RspGF+j].isburst  = 1'b0;
          grouped_resp_valid[i*RspGF+j]          = 1'b0;
          // grouped response is ready if the i*RspGF'th output handshakes
          grouped_resp_ready[i*RspGF+j]          = resp_valid_o[i*RspGF] && resp_ready_i[i*RspGF];
        end

      end
    end

    // Assign outputs
    for (genvar i = 0; i < NumOut; i++) begin
      assign resp_ini_addr_o[i]      = group_mask_q[i] ? grouped_resp_ini_addr[i]      : resp_ini_addr_i[i];
      assign resp_rdata_o[i]         = group_mask_q[i] ? grouped_resp_rdata[i]         : resp_rdata_i[i];
      assign resp_burst_o[i].gdata   = group_mask_q[i] ? grouped_resp_burst[i].gdata   : '0;
      assign resp_burst_o[i].isburst = group_mask_q[i] ? grouped_resp_burst[i].isburst : 1'b0;
      assign resp_valid_o[i]         = group_mask_q[i] ? grouped_resp_valid[i]         : resp_valid_i[i];
      assign resp_ready_o[i]         = group_mask_q[i] ? grouped_resp_ready[i]         : (resp_valid_o[i] && resp_ready_i[i]);
    end
  end

  /******************
   *   Assertions   *
   ******************/
  if (NumOut == 0)
    $error("[burst_manager] NumBanks needs to be greater or equal to 1");

  if (NumOut < RspGF)
    $error("[burst_manager] NumBanks needs to be larger or equal to RspGF");

endmodule : burst_manager
