// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author: Marco Bertuletti ETH Zurich

/// Burst Req Grouper:
/// Packs a parallel memory request from NumIn initiators in a burst request.
/// The burst cutter creates multiple burst requests when the burst request crosses
/// the boundary in the target multi-banked memory.

module burst_req_grouper
  import burst_pkg::burst_t;
  import burst_pkg::burst_gresp_t;
#(
  parameter int unsigned NumIn = 32,
  parameter int unsigned NumOut = 32,
  parameter int unsigned AddrWidth  = 32,
  parameter int unsigned DataWidth  = 32,
  parameter int unsigned BeWidth    = DataWidth/8,
  // Number of Address bits per Target
  parameter int unsigned AddrMemWidth      = 12,
  // Determines the width of the byte offset in a memory word. Normally this can be left at the default value,
  // but sometimes it needs to be overridden (e.g., when metadata is supplied to the memory via the wdata signal).
  parameter int unsigned ByteOffWidth      = $clog2(DataWidth-1)-3,
  // Group Request Extension Grouping Factor for TCDM
  parameter int unsigned  ReqGF = 1,
  // Group Response Extension Grouping Factor for TCDM
  parameter int unsigned  RspGF = 1,
  // Datawidth of words grouped in the burst
  parameter int unsigned GroupedDW = burst_pkg::GroupedDW,
  // Dependant parameters. DO NOT CHANGE!
  parameter int unsigned NumInLog2 = NumIn == 1 ? 1 : $clog2(NumIn)
)(
  input  logic clk_i,
  input  logic rst_ni,
  // Parallel input request port
  input  logic         [NumIn-1:0][NumInLog2-1:0] req_ini_addr_i, // Initiator address
  input  logic         [NumIn-1:0][AddrWidth-1:0] req_tgt_addr_i, // Target address
  input  logic         [NumIn-1:0][DataWidth-1:0] req_wdata_i,
  input  logic         [NumIn-1:0]                req_wen_i,
  input  logic         [NumIn-1:0][BeWidth-1:0]   req_be_i,
  input  logic         [NumIn-1:0]                req_valid_i,
  output logic         [NumIn-1:0]                req_ready_o,
  // Burst output request port
  output logic         [NumIn-1:0][NumInLog2-1:0] req_ini_addr_o, // Initiator address
  output logic         [NumIn-1:0][AddrWidth-1:0] req_tgt_addr_o, // Target address
  output logic         [NumIn-1:0][DataWidth-1:0] req_wdata_o,
  output logic         [NumIn-1:0]                req_wen_o,
  output logic         [NumIn-1:0][BeWidth-1:0]   req_be_o,
  output burst_t       [NumIn-1:0]                req_burst_o,
  output logic         [NumIn-1:0]                req_valid_o,
  input  logic         [NumIn-1:0]                req_ready_i,
  // Response out
  output logic         [NumIn-1:0][NumInLog2-1:0] resp_ini_addr_o,
  output logic         [NumIn-1:0][DataWidth-1:0] resp_rdata_o,
  output logic         [NumIn-1:0]                resp_valid_o,
  input  logic         [NumIn-1:0]                resp_ready_i,
  // Response in
  input  logic         [NumIn-1:0][NumInLog2-1:0] resp_ini_addr_i,
  input  logic         [NumIn-1:0][DataWidth-1:0] resp_rdata_i,
  input  burst_gresp_t [NumIn-1:0]                resp_burst_i,
  input  logic         [NumIn-1:0]                resp_valid_i,
  output logic         [NumIn-1:0]                resp_ready_o
);

  `include "common_cells/registers.svh"
  localparam int unsigned NumGroupReq = ReqGF > 1 ? NumIn >> $clog2(ReqGF) : NumIn;
  localparam int unsigned NumGroupRsp = RspGF > 1 ? NumIn >> $clog2(RspGF) : NumIn;

  /*************/
  /* Request   */
  /*************/

  logic [NumIn-1:0][DataWidth-1:0] req_cutter_wdata;
  logic [NumInLog2-1:0]            req_cutter_ini_addr;
  logic [AddrWidth-1:0]            req_cutter_tgt_addr;
  logic                            req_cutter_wen;
  logic [BeWidth-1:0]              req_cutter_be;
  burst_t                          req_cutter_burst;
  logic                            cutter_ready;

  logic [NumInLog2-1:0] req_bursted_ini_addr;
  logic [AddrWidth-1:0] req_bursted_tgt_addr;
  logic [DataWidth-1:0] req_bursted_wdata;
  logic                 req_bursted_wen;
  logic [BeWidth-1:0]   req_bursted_be;
  burst_t               req_bursted_burst;
  logic                 req_bursted_valid;

  // To verify that the request goes to consecutive addresses
  logic [NumIn-2:0] consecutive;
  logic consecutive_read, consecutive_write;

  always_comb begin

    // Bypass input
    req_ini_addr_o = req_ini_addr_i;
    req_tgt_addr_o = req_tgt_addr_i;
    req_wdata_o    = req_wdata_i;
    req_wen_o      = req_wen_i;
    req_be_o       = req_be_i;
    req_burst_o    = '0;
    req_valid_o    = req_valid_i;
    req_ready_o    = req_ready_i;

    // Check if request goes to consecutive addresses
    for (int i = 0; i < NumIn-1; i++) begin
      consecutive[i] = (req_tgt_addr_i[i+1][AddrWidth-1:ByteOffWidth]
                      - req_tgt_addr_i[i][AddrWidth-1:ByteOffWidth]) == AddrWidth'(1);
    end

    /* WRITE */

    // Assign grouped requests
    if (ReqGF > 1) begin
      for (int i = 0; i < NumGroupReq; i++) begin
        consecutive_write = &consecutive[i*ReqGF+:(ReqGF-1)] && &req_wen_i[i*ReqGF+:ReqGF];
        if (&req_valid_i[i*ReqGF+:ReqGF] && consecutive_write) begin
          req_ini_addr_o[i*ReqGF]           = req_ini_addr_i[i*ReqGF];
          req_tgt_addr_o[i*ReqGF]           = req_tgt_addr_i[i*ReqGF];
          req_wdata_o[i*ReqGF]              = req_wdata_i[i*ReqGF];
          req_wen_o[i*ReqGF]                = req_wen_i[i*ReqGF];
          req_be_o[i*ReqGF]                 = req_be_i[i*ReqGF];
          req_burst_o[i*ReqGF].isburst      = 1'b1;
          req_burst_o[i*ReqGF].blen         = ReqGF;
          req_valid_o[i*ReqGF]              = req_valid_i[i*ReqGF];
          req_ready_o[i*ReqGF]              = req_valid_o[i*ReqGF] && req_ready_i[i*ReqGF];
          for (int j = 1; j < ReqGF; j++) begin
            req_ini_addr_o[i*ReqGF+j]       = '0;
            req_tgt_addr_o[i*ReqGF+j]       = '0;
            req_wdata_o[i*ReqGF+j]          = '0;
            req_wen_o[i*ReqGF+j]            = 1'b0;
            req_be_o[i*ReqGF+j]             = '0;
            req_burst_o[i*ReqGF+j]          = '0;
            req_valid_o[i*ReqGF+j]          = 1'b0;
            req_ready_o[i*ReqGF+j]          = req_valid_o[i*ReqGF] && req_ready_i[i*ReqGF];
            req_burst_o[i*ReqGF].gdata[j-1] = req_wdata_i[i*ReqGF+j][GroupedDW-1:0];
          end
        end
      end
    end

    /* READ */

    // Assign input requests to cutter inputs
    req_cutter_tgt_addr      = req_tgt_addr_i[0];
    req_cutter_wdata         = req_wdata_i;
    req_cutter_wen           = req_wen_i[0];
    req_cutter_be            = req_be_i[0];
    req_cutter_burst.isburst = 1'b0;
    req_cutter_burst.blen    = NumIn;
    req_cutter_burst.gdata   = '0;

    consecutive_read = &consecutive && (~|req_wen_i);

    // Burst the read request
    if (&req_valid_i && consecutive_read) begin
      req_cutter_burst.isburst = 1'b1;
      req_ini_addr_o[0]        = req_bursted_ini_addr;
      req_tgt_addr_o[0]        = req_bursted_tgt_addr;
      req_wdata_o[0]           = req_bursted_wdata;
      req_wen_o[0]             = req_bursted_wen;
      req_be_o[0]              = req_bursted_be;
      req_burst_o[0]           = req_bursted_burst;
      req_valid_o[0]           = req_bursted_valid;
      req_ready_o[0]           = cutter_ready;
      // Silence other ports
      for (int i = 1; i < NumIn; i++) begin
        req_ini_addr_o[i]      = '0;
        req_tgt_addr_o[i]      = '0;
        req_wdata_o[i]         = '0;
        req_wen_o[i]           = 1'b0;
        req_be_o[i]            = '0;
        req_burst_o[i]         = '0;
        req_valid_o[i]         = 1'b0;
        req_ready_o[i]         = cutter_ready;
      end
    end

  end

  burst_cutter #(
    .NumIn        (NumIn        ),
    .NumOut       (NumOut       ),
    .AddrWidth    (AddrWidth    ),
    .DataWidth    (DataWidth    ),
    .BeWidth      (BeWidth      ),
    .AddrMemWidth (AddrMemWidth ),
    .ByteOffWidth (ByteOffWidth )
  ) i_burst_cutter (
    .clk_i           (clk_i  ),
    .rst_ni          (rst_ni ),
    // Memory Request In
    .req_ini_addr_i (req_cutter_ini_addr ),
    .req_tgt_addr_i (req_cutter_tgt_addr ),
    .req_wen_i      (req_cutter_wen      ),
    .req_wdata_i    (req_cutter_wdata    ),
    .req_be_i       (req_cutter_be       ),
    .req_burst_i    (req_cutter_burst    ),
    .req_valid_i    (req_valid_i[0]      ),
    .req_ready_o    (cutter_ready        ),
    // Memory Request Out
    .req_ini_addr_o (req_bursted_ini_addr ),
    .req_tgt_addr_o (req_bursted_tgt_addr ),
    .req_wen_o      (req_bursted_wen      ),
    .req_wdata_o    (req_bursted_wdata    ),
    .req_be_o       (req_bursted_be       ),
    .req_burst_o    (req_bursted_burst    ),
    .req_valid_o    (req_bursted_valid    ),
    .req_ready_i    (req_ready_i[0]       )
  );

  /*************/
  /* Response  */
  /*************/

  if (RspGF == 1) begin: gen_default_assignment

    // Default assignment
    assign resp_ini_addr_o = resp_ini_addr_i;
    assign resp_rdata_o = resp_rdata_i;
    assign resp_valid_o = resp_valid_i;
    assign resp_ready_o = resp_ready_i;

  end else begin: gen_grouped_resp_assignment

    always_comb begin
      // Default assignment
      resp_ini_addr_o = resp_ini_addr_i;
      resp_rdata_o = resp_rdata_i;
      resp_valid_o = resp_valid_i;
      resp_ready_o = resp_ready_i;

      for (int ii = 0; ii < NumGroupRsp; ii++) begin
        if (resp_valid_i[ii*RspGF] && resp_burst_i[ii*RspGF].isburst) begin
          // If the response is grouped only one every RspGF input will be
          // valid. If any of the other inputs is valid give them priority.
          // Otherwise assign to the other ports the response from the
          // (ii*RspGF)'th port and signal them valid.
          if (|resp_valid_o[(ii*RspGF+1)+:(RspGF-1)]) begin
            resp_ini_addr_o[ii*RspGF] = '0;
            resp_rdata_o[ii*RspGF]    = '0;
            resp_valid_o[ii*RspGF]    = 1'b0;
            resp_ready_o[ii*RspGF]    = 1'b0;
          end else begin
            // Assign values from port ii*RspGF
            resp_ini_addr_o[ii*RspGF] = resp_ini_addr_i[ii*RspGF];
            resp_rdata_o[ii*RspGF] = resp_rdata_i[ii*RspGF];
            resp_valid_o[ii*RspGF] = resp_valid_i[ii*RspGF];
            // Send ready back only when all the ports are ready
            resp_ready_o[ii*RspGF] = &resp_ready_i[ii*RspGF+:RspGF];
            for (int jj = 1; jj < RspGF; jj++) begin
              resp_ini_addr_o[ii*RspGF+jj] = resp_ini_addr_i[ii*RspGF] + jj;
              // TODO: This is necessary to assign all the response fields by
              // default to the value of the (ii*RspGF)'th port. It assumes
              // that the actual data payload is in the LSBs.
              resp_rdata_o[ii*RspGF+jj] = (DataWidth > GroupedDW) ? {resp_rdata_i[ii*RspGF][DataWidth-1:GroupedDW], resp_burst_i[ii*RspGF].gdata[jj-1]} :
                                                                    resp_burst_i[ii*RspGF].gdata[jj-1];
              resp_valid_o[ii*RspGF+jj] = resp_valid_i[ii*RspGF];
              resp_ready_o[ii*RspGF+jj] = 1'b0;
            end
          end
        end
      end
    end

  end


endmodule : burst_req_grouper
