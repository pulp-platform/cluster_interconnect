// Copyright 2019 ETH Zurich and University of Bologna.
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
// Date: 07.03.2019
// Description: Full crossbar, implemented as logarithmic interconnect.

module xbar #(
  parameter int unsigned NumIn           = 4,    // only powers of two permitted
  parameter int unsigned NumOut          = 4,    // only powers of two permitted
  parameter int unsigned ReqDataWidth    = 32,   // word width of data
  parameter int unsigned RespDataWidth   = 32,   // word width of data
  parameter int unsigned RespLat         = 1,    // response latency of slaves
  parameter bit          WriteRespOn     = 1'b1, // defines whether the interconnect returns a write response
  parameter bit          BroadCastOn     = 1'b0, // perform broadcast
  parameter bit          ExtPrio         = 1'b1  // use external arbiter priority flags
) (
  input  logic                                  clk_i,
  input  logic                                  rst_ni,
  // master side
  input  logic [NumIn-1:0]                      req_i,     // Request signal
  input  logic [NumIn-1:0][$clog2(NumOut)-1:0]  add_i,     // Bank Address
  input  logic [NumIn-1:0]                      wen_i,     // 1: Store, 0: Load
  input  logic [NumIn-1:0][ReqDataWidth-1:0]    wdata_i,   // Write data
  output logic [NumIn-1:0]                      gnt_o,     // Grant (combinationally dependent on req_i and add_i)
  output logic [NumIn-1:0]                      vld_o,     // Response valid, also asserted if write responses are enabled
  output logic [NumIn-1:0][RespDataWidth-1:0]   rdata_o,   // Data Response DATA (For LOAD commands)
  // slave side
  input  logic [NumOut-1:0][$clog2(NumIn)-1:0]  rr_i,      // External prio input
  input  logic [NumOut-1:0]                     gnt_i,     // Grant input
  output logic [NumOut-1:0]                     req_o,     // Request out
  output logic [NumOut-1:0][ReqDataWidth-1:0]   wdata_o,   // Data request Wire data
  input  logic [NumOut-1:0][RespDataWidth-1:0]  rdata_i    // Data Response DATA (For LOAD commands)
);

  logic [NumOut-1:0][NumIn-1:0][ReqDataWidth-1:0] sl_data;
  logic [NumIn-1:0][NumOut-1:0][ReqDataWidth-1:0] ma_data;
  logic [NumOut-1:0][NumIn-1:0] sl_gnt, sl_req;
  logic [NumIn-1:0][NumOut-1:0] ma_gnt, ma_req;

  // loop over masters and instantiate bank address decoder/resp mux for each master
  for (genvar j=0; unsigned'(j)<NumIn; j++) begin : g_inputs
    addr_dec_resp_mux #(
      .NumOut        ( NumOut        ),
      .ReqDataWidth  ( ReqDataWidth  ),
      .RespDataWidth ( RespDataWidth ),
      .RespLat       ( RespLat       ),
      .BroadCastOn   ( BroadCastOn   ),
      .WriteRespOn   ( WriteRespOn   )
    ) i_addr_dec_resp_mux (
      .clk_i   ( clk_i      ),
      .rst_ni  ( rst_ni     ),
      .req_i   ( req_i[j]   ),
      .add_i   ( add_i[j]   ),
      .wen_i   ( wen_i[j]   ),
      .data_i  ( wdata_i[j] ),
      .gnt_o   ( gnt_o[j]   ),
      .vld_o   ( vld_o[j]   ),
      .rdata_o ( rdata_o[j] ),
      .req_o   ( ma_req[j]  ),
      .gnt_i   ( ma_gnt[j]  ),
      .data_o  ( ma_data[j] ),
      .rdata_i ( rdata_i    )
    );

    // reshape connections between M/S
    for (genvar k=0; unsigned'(k)<NumOut; k++) begin : g_reshape
      assign sl_req[k][j]  = ma_req[j][k];
      assign ma_gnt[j][k]  = sl_gnt[k][j];
      assign sl_data[k][j] = ma_data[j][k];
    end
  end

  // loop over slaves (endpoints)
  // instantiate an RR arbiter for each endpoint
  for (genvar k=0; unsigned'(k)<NumOut; k++) begin : g_outputs
    if(NumIn==1) begin
      assign req_o[k]      = sl_req[k][0];
      assign sl_gnt[k][0]  = gnt_i[k];
      assign wdata_o[k]    = sl_data[k][0];
    end else begin : g_rr_arb_tree
      rr_arb_tree #(
        .NumIn     ( NumIn        ),
        .DataWidth ( ReqDataWidth ),
        .ExtPrio   ( ExtPrio      )
      ) i_rr_arb_tree (
        .clk_i   ( clk_i      ),
        .rst_ni  ( rst_ni     ),
        .flush_i ( 1'b0       ),
        .rr_i    ( rr_i[k]    ),
        .req_i   ( sl_req[k]  ),
        .gnt_o   ( sl_gnt[k]  ),
        .data_i  ( sl_data[k] ),
        .gnt_i   ( gnt_i[k]   ),
        .req_o   ( req_o[k]   ),
        .data_o  ( wdata_o[k] ),
        .idx_o   (            )// disabled
      );
    end
  end

  // pragma translate_off
  initial begin
    assert(2**$clog2(NumIn) == NumIn) else
      $fatal(1,"NumIn is not aligned with a power of 2.");
    assert(2**$clog2(NumOut) == NumOut) else
      $fatal(1,"NumOut is not aligned with a power of 2.");
  end
  // pragma translate_on

endmodule // xbar
