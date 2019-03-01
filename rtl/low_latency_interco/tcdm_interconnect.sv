// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Michael Schaffner <schaffner@iis.ee.ethz.ch>, ETH Zurich
// Date: 19.03.2017
// Description: logarithmic interconnect for TCDM.

module tcdm_interconnect #(
    parameter int unsigned NumMaster      = 256,          // number of initiator ports
    parameter int unsigned NumSlave       = 512,          // number of TCDM banks
    parameter int unsigned AddrWidth      = 32,           // address width on initiator side
    parameter int unsigned DataWidth      = 32,           // word width of data
    parameter int unsigned BeWidth        = DataWidth/8,  // width of corresponding byte enables
    parameter int unsigned AddrMemWidth   = 12,           // number of address bits per TCDM bank
    parameter int unsigned Topology       = 0             // 0 = lic, 1 = bfly
) (
    input  logic                                    clk_i,
    input  logic                                    rst_ni,
    // master side
    input  logic [NumMaster-1:0]                    req_i,     // Data request
    input  logic [NumMaster-1:0][AddrWidth-1:0]     add_i,     // Data request Address
    input  logic [NumMaster-1:0]                    wen_i,     // Data request type : 0--> Store, 1 --> Load
    input  logic [NumMaster-1:0][DataWidth-1:0]     wdata_i,   // Data request Write data
    input  logic [NumMaster-1:0][BeWidth-1:0]       be_i,      // Data request Byte enable
    output logic [NumMaster-1:0]                    gnt_o,     // Grant Incoming Request
    output logic [NumMaster-1:0]                    rvld_o,    // Data Response Valid (For LOAD/STORE commands)
    output logic [NumMaster-1:0][DataWidth-1:0]     rdata_o,   // Data Response DATA (For LOAD commands)
    // slave side
    output  logic [NumSlave-1:0]                    cs_o,      // Chip select for bank
    output  logic [NumSlave-1:0][AddrMemWidth-1:0]  add_o,     // Data request Address
    output  logic [NumSlave-1:0]                    wen_o,     // Data request type : 0--> Store, 1 --> Load
    output  logic [NumSlave-1:0][DataWidth-1:0]     wdata_o,   // Data request Wire data
    output  logic [NumSlave-1:0][BeWidth-1:0]       be_o,      // Data request Byte enable
    input   logic [NumSlave-1:0][DataWidth-1:0]     rdata_i    // Data Response DATA (For LOAD commands)
);

  localparam int unsigned SlaveSelWidth = $clog2(NumSlave);
  localparam int unsigned AddrWordOff   = $clog2(DataWidth-1)-3;
  localparam int unsigned AggDataWidth  = 1+BeWidth+AddrMemWidth+DataWidth;
  logic [NumMaster-1:0][AggDataWidth-1:0] data_agg_in;
  logic [NumSlave-1:0][AggDataWidth-1:0]  data_agg_out;
  logic [NumMaster-1:0][SlaveSelWidth-1:0] bank_sel;

  for (genvar j=0; unsigned'(j)<NumMaster; j++) begin
    // extract bank index
    assign bank_sel[j] = add_i[j][AddrWordOff+SlaveSelWidth-1:AddrWordOff];
    // aggregate data to be routed to slaves
    assign data_agg_in[j] = {wen_i[j], be_i[j], add_i[j][AddrWordOff+SlaveSelWidth+AddrMemWidth-1:AddrWordOff+SlaveSelWidth], wdata_i[j]};
  end

  // disaggregate data
  for (genvar k=0; unsigned'(k)<NumSlave; k++) begin
    assign {wen_o[k], be_o[k], add_o[k], wdata_o[k]} = data_agg_out[k];
  end

  /////////////////////////////////////////////////////////////////////
  // tuned logarithmic interconnect architecture, based on rr_arb_tree primitives
  if (Topology==0) begin

    logic [NumSlave-1:0][NumMaster-1:0][AggDataWidth-1:0]  sl_data;
    logic [NumMaster-1:0][NumSlave-1:0][AggDataWidth-1:0]  ma_data;
    logic [NumSlave-1:0][NumMaster-1:0] sl_gnt, sl_req;
    logic [NumMaster-1:0][NumSlave-1:0] ma_gnt, ma_req;

    // loop over slaves (endpoints)
    // instantiate an RR arbiter for each endpoint
    for (genvar k=0; unsigned'(k)<NumSlave; k++) begin
      rr_arb_tree #(
        .NumReq    ( NumMaster    ),
        .DataWidth ( AggDataWidth )
      ) i_rr_arb_tree (
        .clk_i  ( clk_i           ),
        .rst_ni ( rst_ni          ),
        .req_i  ( sl_req[k]       ),
        .gnt_o  ( sl_gnt[k]       ),
        .data_i ( sl_data[k]      ),
        .gnt_i  ( 1'b1            ),// TCDM is always ready
        .req_o  ( cs_o[k]         ),
        .data_o ( data_agg_out[k] ),
        .idx_o  (                 )
      );
    end

    // loop over masters and instantiate bank address decoder/resp mux for each master
    for (genvar j=0; unsigned'(j)<NumMaster; j++) begin
      addr_dec_resp_mux #(
        .NumSlave      ( NumSlave     ),
        .ReqDataWidth  ( AggDataWidth ),
        .RespDataWidth ( DataWidth    ),
        .RespLat       ( 1            )
      ) i_addr_dec_resp_mux (
        .clk_i  ( clk_i          ),
        .rst_ni ( rst_ni         ),
        .req_i  ( req_i[j]       ),
        .sel_i  ( bank_sel[j]    ),
        .data_i ( data_agg_in[j] ),
        .gnt_o  ( gnt_o[j]       ),
        .rvld_o ( rvld_o[j]      ),
        .rdata_o( rdata_o[j]     ),
        .req_o  ( ma_req[j]      ),
        .gnt_i  ( ma_gnt[j]      ),
        .data_o ( ma_data[j]     ),
        .rdata_i( rdata_i        )
      );

      // reshape connections between M/S
      for (genvar k=0; unsigned'(k)<NumSlave; k++) begin
        assign sl_req[k][j]  = ma_req[j][k];
        assign ma_gnt[j][k]  = sl_gnt[k][j];
        assign sl_data[k][j] = ma_data[j][k];
      end
    end
  /////////////////////////////////////////////////////////////////////
  // scalable interconnect using a butterfly network
  end else if (Topology==1) begin
    bfly_net #(
      .NumIn(NumMaster),
      .NumOut(NumSlave),
      .ReqDataWidth(AggDataWidth),
      .RespDataWidth(DataWidth)
    ) i_bfly_net (
      .clk_i    ( clk_i        ),
      .rst_ni   ( rst_ni       ),
      .req_i    ( req_i        ),
      .gnt_o    ( gnt_o        ),
      .sel_i    ( bank_sel     ),
      .data_i   ( data_agg_in  ),
      .rdata_o  ( rdata_o      ),
      .rvld_o   ( rvld_o       ),
      .req_o    ( cs_o         ),
      .gnt_i    ( '1           ),
      .data_o   ( data_agg_out ),
      .rdata_i  ( rdata_i      )
    );
  /////////////////////////////////////////////////////////////////////
  end else begin
    // pragma translate_off
    initial begin
      $fatal(1,"Unknown TCDM configuration %d. Choose either 0 for lic or 1 for bfly", Topology);
    end
    // pragma translate_on
  end
  /////////////////////////////////////////////////////////////////////


  // pragma translate_off
  initial begin
    assert(AddrMemWidth+SlaveSelWidth+AddrMemWidth <= AddrWidth) else
      $fatal(1,"Address not wide enough to accomodate the requested TCDM configuration.");
  end
  // pragma translate_on

endmodule
