// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Author: Diyou Shen ETH Zurich
// Author: Marco Bertuletti ETH Zurich

/// Burst Cutter:
/// Divides the burst request from NumIn initiators in multiple bursts when it
/// crosses the address boundary in the target multi-banked Memory.

module burst_cutter
  import burst_pkg::burst_t;
#(
  parameter int unsigned NumIn = 32,
  parameter int unsigned NumOut = 64,
  parameter int unsigned AddrWidth = 32,
  parameter int unsigned DataWidth = 32,
  parameter int unsigned BeWidth = DataWidth/8,
  // Number of Address bits per Target
  parameter int unsigned AddrMemWidth = 12,
  // Determines the width of the byte offset in a memory word. Normally this can be left at the default value,
  // but sometimes it needs to be overridden (e.g., when metadata is supplied to the memory via the wdata signal).
  parameter int unsigned ByteOffWidth = $clog2(DataWidth-1)-3,
  // Dependant parameters. DO NOT CHANGE!
  parameter int unsigned NumInLog2 = (NumIn == 1) ? 1 : $clog2(NumIn)
) (
  input  logic clk_i,
  input  logic rst_ni,
  // Memory Request In
  input  logic   [NumInLog2-1:0]            req_ini_addr_i, // Initiator address
  input  logic   [AddrWidth-1:0]            req_tgt_addr_i, // Target address
  input  logic                              req_wen_i,      // Write enable
  input  logic   [NumIn-1:0][DataWidth-1:0] req_wdata_i,    // Write data
  input  logic   [BeWidth-1:0]              req_be_i,       // Byte enable
  input  burst_t                            req_burst_i,    // Burst data
  input  logic                              req_valid_i,
  output logic                              req_ready_o,
  // Memory Request Out
  output logic   [NumInLog2-1:0]            req_ini_addr_o, // Initiator address
  output logic   [AddrWidth-1:0]            req_tgt_addr_o, // Target address
  output logic                              req_wen_o,      // Write enable
  output logic   [DataWidth-1:0]            req_wdata_o,    // Write data
  output logic   [BeWidth-1:0]              req_be_o,       // Byte enable
  output burst_t                            req_burst_o,    // Burst data
  output logic                              req_valid_o,
  input  logic                              req_ready_i
);

  `include "common_cells/registers.svh"

  localparam int unsigned BurstLen = NumIn;
  localparam int unsigned BurstLenWidth = NumInLog2;
  localparam int unsigned NumBanks = NumOut;
  localparam int unsigned BankOffsetBits = AddrMemWidth - ByteOffWidth;

  typedef enum logic {
    Bypass, // normal requests, first cut of burst
    BurstCut // second cut of burst
  } burst_cutter_fsm_e;

  logic [31:0] bank_offset;
  logic [31:0] max_blen;
  logic [31:0] remaining_len;
  assign bank_offset = {{(32-BankOffsetBits){1'b0}}, req_tgt_addr_i[AddrMemWidth-1 : ByteOffWidth]};
  assign max_blen = NumBanks - bank_offset;
  assign remaining_len = {{(32-BurstLenWidth){1'b0}}, req_burst_i.blen} > max_blen ?
                          {{(32-BurstLenWidth){1'b0}}, req_burst_i.blen} - max_blen : '0;

  // FSM state
  burst_cutter_fsm_e  state_d, state_q;
  burst_cutter_fsm_e  next_state;

  // FSM stored signals
  logic [NumInLog2-1:0] cut_ini_addr_d, cut_ini_addr_q;
  logic [AddrWidth-1:0] cut_tgt_addr_d, cut_tgt_addr_q;
  logic [DataWidth-1:0] cut_wdata_d, cut_wdata_q;
  burst_t               cut_burst_d, cut_burst_q;

  // Store FSM state and signals
  `FF(state_q, state_d, Bypass, clk_i, rst_ni);
  `FF(cut_burst_q, cut_burst_d, '0, clk_i, rst_ni);
  `FF(cut_ini_addr_q, cut_ini_addr_d, '0, clk_i, rst_ni);
  `FF(cut_tgt_addr_q, cut_tgt_addr_d, '0, clk_i, rst_ni);
  `FF(cut_wdata_q, cut_wdata_d, '0, clk_i, rst_ni);

  always_comb begin

    // FSM defaults
    state_d        = state_q;
    cut_burst_d    = cut_burst_q;
    cut_tgt_addr_d = cut_tgt_addr_q;
    cut_ini_addr_d = cut_ini_addr_q;
    cut_wdata_d    = cut_wdata_q;

    // Need to cut, use FSM to realize the logic
    case (state_q)

      Bypass: begin

        // Bypass the signals
        req_ini_addr_o = req_ini_addr_i;
        req_tgt_addr_o = req_tgt_addr_i;
        req_wdata_o    = req_wdata_i[0];
        req_wen_o      = req_wen_i;
        req_be_o       = req_be_i;
        req_burst_o    = req_burst_i;
        req_valid_o    = req_valid_i;
        req_ready_o    = req_ready_i;

        // Check if it is valid and being a burst request
        if (req_burst_i.isburst) begin

          // No support for write burst, tie to 0
          if (req_wen_i) begin
            req_burst_o = '0;

          end else begin

            // Cut burst when it is longer than the max length
            if (remaining_len > 0) begin

              // Send out the first burst
              req_burst_o.isburst = 1'b1;
              req_burst_o.blen    = max_blen;
              req_burst_o.gdata   = '0;
              // store the info for next burst
              cut_ini_addr_d      = req_ini_addr_i + (max_blen << ByteOffWidth);
              cut_tgt_addr_d      = req_tgt_addr_i + (max_blen << ByteOffWidth);
              cut_wdata_d         = req_wdata_i[max_blen];
              cut_burst_d.isburst = 1'b1;
              cut_burst_d.blen    = remaining_len[BurstLenWidth-1:0];
              cut_burst_d.gdata   = '0;

              // pause taking in new requests
              req_ready_o = 1'b0;
              // Keep state until the current one is picked
              if (req_ready_i) begin
                state_d = BurstCut;
              end
            end

          end
        end

      end

      BurstCut: begin

        // Send out second half and wait for ready
        req_tgt_addr_o = cut_ini_addr_q;
        req_tgt_addr_o = cut_tgt_addr_q;
        req_wdata_o    = cut_wdata_q;
        req_wen_o      = '0; // only read burst is supported
        req_be_o       = '0;
        req_burst_o    = cut_burst_q;
        req_valid_o    = 1'b1;
        req_ready_o    = 1'b0;

        // When we get the ready, the second part is out
        if (req_ready_i) begin
          req_ready_o   = req_ready_i;
          state_d       = Bypass;
        end

      end

      default: state_d = Bypass;
    endcase
  end

  /******************
   *   Assertions   *
   ******************/

  if (BurstLen > NumBanks)
    $fatal(1, "Only one cut is supported, reduce the burst length.");

endmodule : burst_cutter
