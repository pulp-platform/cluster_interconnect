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
// Description: Clos node (full crossbar, lic implementation). Can be parameterized as
// ingress, middle / egress node

module clos_node #(
  parameter int unsigned NumIn           = 4,            // R parameter only powers of two permitted
  parameter int unsigned NumOut          = 4,            // R parameter only powers of two permitted
  parameter int unsigned AddrWidth       = 32,           // address width on initiator side
  parameter int unsigned DataWidth       = 32,           // word width of data
  parameter int unsigned MemLatency      = 1,
  parameter bit          NodeType        = 0             // 0: ingress type, 1: middle / egress type
) (
  input  logic                                  clk_i,
  input  logic                                  rst_ni,
  // master side
  input  logic [NumIn-1:0]                      req_i,     // Request signal
  input  logic [NumIn-1:0][AddrWidth-1:0]       add_i,     // Bank Address
  input  logic [NumIn-1:0][DataWidth-1:0]       wdata_i,   // Write data
  output logic [NumIn-1:0]                      gnt_o,     // Grant (combinationally dependent on req_i and add_i)
  output logic [NumIn-1:0][DataWidth-1:0]       rdata_o,   // Data Response DATA (For LOAD commands)
  // slave side
  output  logic [NumOut-1:0]                    gnt_i,     // Grant input
  output  logic [NumOut-1:0]                    req_o,     // Request out
  output  logic [NumOut-1:0][AddrWidth-1:0]     add_o,     // Bank Address
  output  logic [NumOut-1:0][DataWidth-1:0]     wdata_o,   // Data request Wire data
  input   logic [NumOut-1:0][DataWidth-1:0]     rdata_i    // Data Response DATA (For LOAD commands)
);

  localparam int unsigned AggDataWidth  = DataWidth + AddrWidth;
  logic [NumMaster-1:0][AggDataWidth-1:0] data_agg_in;
  logic [NumSlave-1:0][AggDataWidth-1:0]  data_agg_out;
  logic [NumMaster-1:0][$clog2(NumOut)-1:0] bank_sel;


  for (genvar j=0; unsigned'(j)<NumMaster; j++) begin : g_inputs
    // extract bank index
    assign bank_sel[j] = add_i[j][AddrWidth-1:AddrWidth-$clog2(NumOut)-1];
    // aggregate data to be routed to outputs
    assign data_agg_in[j] = {add_i[j], wdata_i[j]};
  end

  // disaggregate data
  for (genvar k=0; unsigned'(k)<NumSlave; k++) begin : g_outputs
    assign {add_o[k], wdata_o[k]} = data_agg_out[k];
  end

  // loop over masters and instantiate bank address decoder/resp mux for each master
  for (genvar j=0; unsigned'(j)<NumIn; j++) begin : g_inputs
    addr_dec_resp_mux #(
      .NumSlave      ( NumOut     ),
      .ReqDataWidth  ( AggDataWidth ),
      .RespDataWidth ( DataWidth    ),
      .RespLat       ( MemLatency   )
    ) i_addr_dec_resp_mux (
      .clk_i  ( clk_i          ),
      .rst_ni ( rst_ni         ),
      .req_i  ( req_i[j]       ),
      .add_i  ( bank_sel[j]    ),// MSBs of bank address
      .data_i ( data_agg_in[j] ),
      .gnt_o  ( gnt_o[j]       ),
      .rdata_o( rdata_o[j]     ),
      .req_o  ( ma_req[j]      ),
      .gnt_i  ( ma_gnt[j]      ),
      .data_o ( ma_data[j]     ),
      .rdata_i( rdata_i        )
    );

    // reshape connections between M/S
    for (genvar k=0; unsigned'(k)<NumSlave; k++) begin : g_reshape
      assign sl_req[k][j]  = ma_req[j][k];
      assign ma_gnt[j][k]  = sl_gnt[k][j];
      assign sl_data[k][j] = ma_data[j][k];
    end
  end

  // loop over slaves (endpoints)
  // instantiate an RR arbiter for each endpoint
  for (genvar k=0; unsigned'(k)<NumOut; k++) begin : g_outputs
    rr_arb_tree #(
      .NumReq    ( NumIn    ),
      .DataWidth ( AggDataWidth )
    ) i_rr_arb_tree (
      .clk_i  ( clk_i           ),
      .rst_ni ( rst_ni          ),
      .req_i  ( sl_req[k]       ),
      .gnt_o  ( sl_gnt[k]       ),
      .data_i ( sl_data[k]      ),
      .gnt_i  ( gnt_i[k]        ),
      .req_o  ( req_o[k]        ),
      .data_o ( data_agg_out[k] ),
      .idx_o  (                 )// disabled
    );
  end

  // pragma translate_off
  initial begin
    assert(2**$clog2(NumIn) == NumIn) else
      $fatal(1,"NumIn is not aligned with a power of 2.");
    assert(2**$clog2(NumOut) == NumOut) else
      $fatal(1,"NumOut is not aligned with a power of 2.");
  end
  // pragma translate_on

endmodule
