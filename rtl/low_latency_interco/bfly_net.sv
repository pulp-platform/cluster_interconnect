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
// Description: logarithmic arbitration tree for TCDM with round robin arbitration.

module bfly_net #(
  parameter int unsigned NumIn         = 32,
  parameter int unsigned NumOut        = 32,
  parameter int unsigned ReqDataWidth  = 32,
  parameter int unsigned RespDataWidth = 32,
  // routers per level, do not change (max operation)
  parameter int unsigned NumRouters    = 2**$clog2((NumIn > NumOut) * NumIn + (NumIn <= NumOut) * NumOut)/2,
  parameter int unsigned NumLevels     = $clog2(NumOut)

) (
  input  logic                                 clk_i,
  input  logic                                 rst_ni,
  // master ports
  input  logic [NumIn-1:0]                     req_i,
  output logic [NumIn-1:0]                     gnt_o,
  input  logic [NumIn-1:0][NumLevels-1:0]      add_i,
  input  logic [NumIn-1:0][ReqDataWidth-1:0]   data_i,
  output logic [NumIn-1:0][RespDataWidth-1:0]  rdata_o,
  output logic [NumIn-1:0]                     rvld_o,
  // slave ports
  output logic [NumOut-1:0]                    req_o,
  input  logic [NumOut-1:0]                    gnt_i,
  output logic [NumOut-1:0][ReqDataWidth-1:0]  data_o,
  input  logic [NumOut-1:0][RespDataWidth-1:0] rdata_i
);

  localparam int unsigned BankingFact = NumOut/NumIn;

  logic [NumLevels-1:0][NumRouters-1:0][1:0]                    router_req_in;
  logic [NumLevels-1:0][NumRouters-1:0][1:0]                    router_req_out;
  logic [NumLevels-1:0][NumRouters-1:0][1:0]                    router_gnt_in;
  logic [NumLevels-1:0][NumRouters-1:0][1:0]                    router_gnt_out;
  logic [NumLevels-1:0][NumRouters-1:0][1:0][NumLevels-1:0]     router_add_in;
  logic [NumLevels-1:0][NumRouters-1:0][1:0][NumLevels-1:0]     router_add_out;
  logic [NumLevels-1:0][NumRouters-1:0][1:0][ReqDataWidth-1:0]  router_data_in;
  logic [NumLevels-1:0][NumRouters-1:0][1:0][ReqDataWidth-1:0]  router_data_out;
  logic [NumLevels-1:0][NumRouters-1:0][1:0][RespDataWidth-1:0] router_resp_data_in;
  logic [NumLevels-1:0][NumRouters-1:0][1:0][RespDataWidth-1:0] router_resp_data_out;


  logic [NumLevels-1:0][NumRouters-1:0]                         collision;
  logic [NumLevels-1:0][NumRouters-1:0]                         router_state_d, router_state_q;
  logic [NumIn-1:0]                                             rvld_d, rvld_q;

  // // inputs are on first level
  // make sure to evenly distribute masters in case of BankingFactors > 1
  for (genvar j = 0; unsigned'(j) < 2*NumRouters; j++) begin
    if(j % BankingFact == 0) begin
      // req
      assign router_req_in[0][j/2][j%2]  = req_i[j/BankingFact];
      assign gnt_o[j/BankingFact]        = router_gnt_out[0][j/2][j%2];
      assign router_add_in[0][j/2][j%2]  = add_i[j/BankingFact];
      assign router_data_in[0][j/2][j%2] = data_i[j/BankingFact];
      // resp
      assign rdata_o[j/BankingFact]      = router_resp_data_out[0][j/2][j%2];
    end else begin
      // req
      assign router_req_in[0][j/2][j%2]  = 1'b0;
      assign router_add_in[0][j/2][j%2]  = '0;
      assign router_data_in[0][j/2][j%2] = '0;
    end
  end

  // outputs are on last level
  for (genvar j = 0; unsigned'(j) < 2*NumRouters; j++) begin
    if (j < NumOut) begin
      // req
      assign req_o[j]                                   = router_req_out[NumLevels-1][j/2][j%2];
      assign router_gnt_in[NumLevels-1][j/2][j%2]       = gnt_i[j];
      assign data_o[j]                                  = router_data_out[NumLevels-1][j/2][j%2];
      // resp
      assign router_resp_data_in[NumLevels-1][j/2][j%2] = rdata_i[j];
    end else begin
      // req
      assign router_gnt_in[NumLevels-1][j/2][j%2]       = 1'b0;
      // resp
      assign router_resp_data_in[NumLevels-1][j/2][j%2] = '0;
    end
  end

  // wire up connections between levels
  for (genvar l = 0; unsigned'(l) < NumLevels-1; l++) begin : g_levels
    for (genvar r = 0; unsigned'(r) < NumRouters; r++) begin : g_routers
      localparam pow = 2**(NumLevels-l-2);
      localparam s0 = (r / pow    ) % 2;
      localparam s1 = (r / pow + 1) % 2;
      localparam d0 = (r / pow    ) % 2;
      localparam d1 = (r / pow    ) % 2;

      // straight connection on output s0
      assign router_req_in[l+1][r][d0]      = router_req_out[l][r][s0];
      assign router_add_in[l+1][r][d0]      = router_add_out[l][r][s0];
      assign router_data_in[l+1][r][d0]     = router_data_out[l][r][s0];
      assign router_gnt_in[l][r][s0]        = router_gnt_out[l+1][r][d0];
      assign router_resp_data_in[l][r][s0]  = router_resp_data_out[l+1][r][d0];
      // introduce power of two jumps on output s1
      if ((r / pow) % 2) begin
        assign router_req_in[l+1][r - pow][d1]  = router_req_out[l][r][s1];
        assign router_add_in[l+1][r - pow][d1]  = router_add_out[l][r][s1];
        assign router_data_in[l+1][r - pow][d1] = router_data_out[l][r][s1];
        assign router_gnt_in[l][r][s1]          = router_gnt_out[l+1][r - pow][d1];
        assign router_resp_data_in[l][r][s1]    = router_resp_data_out[l+1][r - pow][d1];
      end else begin
        assign router_req_in[l+1][r + pow][d1]  = router_req_out[l][r][s1];
        assign router_add_in[l+1][r + pow][d1]  = router_add_out[l][r][s1];
        assign router_data_in[l+1][r + pow][d1] = router_data_out[l][r][s1];
        assign router_gnt_in[l][r][s1]          = router_gnt_out[l+1][r + pow][d1];
        assign router_resp_data_in[l][r][s1]    = router_resp_data_out[l+1][r + pow][d1];
      end
    end
  end

  // instantiate butterfly routers
  for (genvar l = 0; unsigned'(l) < NumLevels; l++) begin
    for (genvar r = 0; unsigned'(r) < NumRouters; r++) begin
      bfly_router #(
        .NumLevels     ( NumLevels     ),
        .ReqDataWidth  ( ReqDataWidth  ),
        .RespDataWidth ( RespDataWidth )
      ) i_bfly_router (
        .clk_i  ( clk_i                      ),
        .rst_ni ( rst_ni                     ),
        .req_i  ( router_req_in[l][r]        ),
        .gnt_o  ( router_gnt_out[l][r]       ),
        .sel_i  ( {router_add_in[l][r][1][NumLevels-l-1], router_add_in[l][r][0][NumLevels-l-1]}),
        .add_i  ( router_add_in[l][r]        ),
        .data_i ( router_data_in[l][r]       ),
        .rdata_o( router_resp_data_out[l][r] ),
        .req_o  ( router_req_out[l][r]       ),
        .gnt_i  ( router_gnt_in[l][r]        ),
        .add_o  ( router_add_out[l][r]       ),
        .data_o ( router_data_out[l][r]      ),
        .rdata_i( router_resp_data_in[l][r]  )
      );
    end
  end

  assign rvld_d = gnt_o;
  assign rvld_o = rvld_q;

  always_ff @(posedge clk_i) begin : p_regs
    if(~rst_ni) begin
      rvld_q <= '0;
    end else begin
      rvld_q <= rvld_d;
    end
  end

endmodule // bfly_net