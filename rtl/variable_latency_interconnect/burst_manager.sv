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
  // Group Request Extension Grouping Factor for TCDM
  parameter int unsigned ReqGF = 1,
  // Group Response Extension Grouping Factor for TCDM
  parameter int unsigned RspGF = 1,
  // Datawidth of words grouped in the burst
  parameter int unsigned GroupedDW = burst_pkg::GroupedDW,
  // Dependant parameters. DO NOT CHANGE!
  parameter int unsigned NumInLog2 = (NumIn > 32'd1) ? unsigned'($clog2(NumIn)) : 32'd1,
  parameter int unsigned NumOutLog2 = (NumOut > 32'd1) ? unsigned'($clog2(NumOut)) : 32'd1
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
  output burst_gresp_t [NumOut-1:0]                resp_burst_o,
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

  localparam int unsigned NumGroupReq = ReqGF > 0 ? NumOut >> $clog2(ReqGF) : NumOut;
  localparam int unsigned NumGroupRsp = RspGF > 0 ? NumOut >> $clog2(RspGF) : NumOut;

  typedef struct packed {
    logic   [NumInLog2-1:0] ini_addr;
    logic   [AddrWidth-1:0] tgt_addr;
    logic   [DataWidth-1:0] wdata;
    logic                   wen;
    logic   [BeWidth-1:0]   ben;
    burst_t                 burst;
  } arb_data_t;

  typedef struct packed {
    logic   [NumInLog2-1:0]  ini_addr;
    logic   [AddrWidth-1:0]  tgt_addr;
    logic   [DataWidth-1:0]  wdata;
    logic                    wen;
    logic   [BeWidth-1:0]    ben;
    burst_t                  burst;
    logic   [NumOutLog2-1:0] idx;
  } fifo_data_t;

  // Internal signals
  logic   [NumOut-1:0]         req_valid;
  burst_gresp_t [NumOut-1:0]   resp_burst;
  logic         [NumOut-1:0]   resp_valid;
  logic         [NumOut-1:0]   resp_ready;

  arb_data_t [NumOut-1:0]      prearb_data;
  logic      [NumOut-1:0]      prearb_valid, prearb_ready;
  arb_data_t                   postarb_data;
  logic                        postarb_valid, postarb_ready;
  logic      [NumOutLog2-1:0]  postarb_idx;

  fifo_data_t   fifo_data, pre_fifo_data;
  logic         fifo_pop, fifo_empty, fifo_full, fifo_push;

  always_comb begin

    req_valid      = req_valid_i;
    prearb_data    = '0;
    prearb_valid   = '0;

    for (int unsigned i = 0; i < NumOut; i++) begin
      if (req_burst_i[i].isburst) begin
        prearb_data[i].ini_addr = req_ini_addr_i[i];
        prearb_data[i].tgt_addr = req_tgt_addr_i[i];
        prearb_data[i].wdata    = req_wdata_i[i];
        prearb_data[i].wen      = req_wen_i[i];
        prearb_data[i].ben      = req_be_i[i];
        prearb_data[i].burst    = req_burst_i[i];
        prearb_valid[i]         = 1'b1;
        req_valid[i]            = 1'b0;
      end
    end
  end

  rr_arb_tree #(
    .NumIn     ( NumOut     ),
    .DataType  ( arb_data_t ),
    .ExtPrio   ( 1'b0       ),
    .AxiVldRdy ( 1'b1       ),
    .LockIn    ( 1'b1       )
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

  typedef enum logic[1:0] {
    Idle, // idle until burst request comes
    DoBurstWrite,
    DoBurstRead
  } req_gen_fsm_e;

  // FSM state & signals
  req_gen_fsm_e state_d, state_q;
  fifo_data_t req_d, req_q;

  // Indicates which req inputs are involved in a burst
  logic [NumOut-1:0] burst_req_mask_d, burst_req_mask_q;
  // Indicates which resp inputs are involved in a burst
  logic [NumOut-1:0] burst_resp_mask_d, burst_resp_mask_q;
  // indicates if there is pending req/resp to be picked
  logic pending_req, pending_rsp;

  // Store FSM state and signals
  `FF(state_q, state_d, Idle, clk_i, rst_ni);
  `FF(req_q, req_d, '0, clk_i, rst_ni);
  `FF(burst_req_mask_q, burst_req_mask_d, '0, clk_i, rst_ni);
  `FF(burst_resp_mask_q, burst_resp_mask_d, '0, clk_i, rst_ni);

  assign resp_ini_addr_o = resp_ini_addr_i;
  assign resp_rdata_o    = resp_rdata_i;
  assign resp_burst_o    = resp_burst;
  assign resp_valid_o    = resp_valid;
  assign resp_ready_o    = resp_ready;

  always_comb begin : request_generator

    // FSM defaults
    state_d           = state_q;
    req_d             = req_q;
    burst_req_mask_d  = burst_req_mask_q;
    burst_resp_mask_d = burst_resp_mask_q;

    // Do not take in next burst for now
    fifo_pop = 1'b0;

    // Bypass all requests by default
    req_wdata_o    = req_wdata_i;
    req_ini_addr_o = req_ini_addr_i;
    req_tgt_addr_o = req_tgt_addr_i;
    req_wen_o      = req_wen_i;
    req_be_o       = req_be_i;

    resp_burst = '0;
    resp_valid = resp_valid_i;
    resp_ready = resp_ready_i;

    // Redistribute burst responses
    if (RspGF > 1) begin
      for (int i = 0; i < NumGroupRsp; i++) begin
        if (burst_resp_mask_q[i*RspGF] && &resp_valid_i[i*RspGF+:RspGF]) begin
          // Send valid only when all the grouped responses are valid
          resp_valid[i*RspGF]         = &resp_valid_i[i*RspGF+:RspGF];
          resp_burst[i*RspGF].isburst = resp_valid[i*RspGF];
          // Send ready and clear mask when handshake occurs
          resp_ready[i*RspGF+:RspGF]        = {RspGF{resp_valid[i*RspGF] & resp_ready_i[i*RspGF]}};
          burst_resp_mask_d[i*RspGF+:RspGF] = ~{RspGF{resp_valid[i*RspGF] & resp_ready_i[i*RspGF]}};
          // Assign input data to grouped response
          for (int j = 1; j < RspGF; j++) begin
            resp_valid[i*RspGF+j]          = 1'b0;
            resp_burst[i*RspGF+j].isburst  = 1'b0;
            resp_burst[i*RspGF].gdata[j-1] = resp_rdata_i[i*RspGF+j][GroupedDW-1:0];
          end
        end
      end
    end

    case (state_q)

      // Idle state, ready to take in burst request
      Idle: begin

        // Let valid requests not in burst pass
        req_valid_o = req_valid;
        req_ready_o = (req_valid & req_ready_i) | (prearb_valid & prearb_ready);

        // Select banks for burst
        burst_req_mask_d  = ((1'b1 << fifo_data.burst.blen) - 1'b1) << fifo_data.idx;
        // Check if there is a request on the affected banks
        pending_req = |(req_valid & burst_req_mask_d);
        // Wait until previous burst responses on the same banks are consumed
        pending_rsp = |(resp_valid & burst_req_mask_d);

        // Start pending burst
        if (!fifo_empty && !pending_req && !pending_rsp) begin
          fifo_pop = 1'b1;
          req_d    = fifo_data;
          state_d  = fifo_data.wen ? DoBurstWrite : DoBurstRead;
        end

      end

      DoBurstWrite: begin

        // Let valid requests not in burst pass
        req_valid_o = req_valid & ~burst_req_mask_q;
        req_ready_o = ((req_valid & req_ready_i) & ~burst_req_mask_q) | (prearb_valid & prearb_ready);

        for (int unsigned i = 0; i < NumOut; i++) begin
          if (burst_req_mask_q[i]) begin
            req_ini_addr_o[i] = i + req_q.ini_addr - req_q.idx;
            req_tgt_addr_o[i] = i + req_q.tgt_addr - req_q.idx;
            req_wen_o[i]      = req_q.wen;
            req_be_o[i]       = req_q.ben;
            req_valid_o[i]    = 1'b1;
            if (i == req_q.idx) begin
              req_wdata_o[i] = req_q.wdata;
              for (int j = 1; j < ReqGF; j++) begin
                req_wdata_o[i+j][DataWidth-1:GroupedDW] = req_q.wdata[DataWidth-1:GroupedDW];
                req_wdata_o[i+j][GroupedDW-1:0]         = req_q.burst.gdata[j-1];
              end
            end
          end
        end

        if ((burst_req_mask_q & req_ready_i) == burst_req_mask_q) begin
          state_d = Idle;
        end

      end

      DoBurstRead: begin

        // Let valid requests not in burst pass
        req_valid_o = req_valid & ~burst_req_mask_q;
        req_ready_o = ((req_valid & req_ready_i) & ~burst_req_mask_q) | (prearb_valid & prearb_ready);

        for (int unsigned i = 0; i < NumOut; i++) begin
          // Overwrite the request on affected banks
          if (burst_req_mask_q[i]) begin
            req_wdata_o[i]    = req_q.wdata;
            req_tgt_addr_o[i] = i + req_q.tgt_addr - req_q.idx;
            req_ini_addr_o[i] = i + req_q.ini_addr - req_q.idx;
            req_wen_o[i]      = req_q.wen;
            req_be_o[i]       = req_q.ben;
            // Set the valid for burst requests
            req_valid_o[i]    = 1'b1;
          end
        end

        if ((burst_req_mask_q & req_ready_i) == burst_req_mask_q) begin
          burst_resp_mask_d = burst_resp_mask_d | burst_req_mask_q;
          state_d = Idle;
        end

      end

      default: state_d = Idle;
    endcase
  end

  /******************
   *   Assertions   *
   ******************/
  if (NumOut == 0)
    $error("[burst_manager] NumBanks needs to be greater or equal to 1");

  if (NumOut < RspGF)
    $error("[burst_manager] NumBanks needs to be larger or equal to RspGF");

endmodule : burst_manager
