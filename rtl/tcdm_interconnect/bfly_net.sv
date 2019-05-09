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
// Date: 06.03.2019
// Description: Radix-2/4 butterfly network. If parameterized to Radix-4,
// the network will be built with 4x4 xbar switchboxes, but depending on the
// amount of end-points, a Radix-2 layer will be added to accomodate non-power
// of 4 parameterizations.
//
// Note that additional radices would not be too difficult to add - just the mixed
// radix layers need to be written in parametric form in order to accommodate
// non-power-of-radix parameterizations.

module bfly_net #(
  parameter int unsigned NumIn           = 32,    // needs to be a power of 2
  parameter int unsigned NumOut          = 32,    // needs to be a power of 2
  parameter int unsigned ReqDataWidth    = 32,
  parameter int unsigned RespDataWidth   = 32,
  parameter bit          WriteRespOn     = 1,
  parameter int unsigned RespLat         = 1,     // defines whether the interconnect returns a write response
  parameter bit          ExtPrio         = 1'b0,  // enable external prio flag input
  parameter int unsigned Radix           = 2      // currently supported: 2 or 4
) (
  input  logic                                  clk_i,
  input  logic                                  rst_ni,
  // external prio flag input
  input  logic [$clog2(NumOut)-1:0]             rr_i,
  // master ports
  input  logic [NumIn-1:0]                      req_i,
  output logic [NumIn-1:0]                      gnt_o,
  input  logic [NumIn-1:0][$clog2(NumOut)-1:0]  add_i,
  input  logic [NumIn-1:0]                      wen_i,
  input  logic [NumIn-1:0][ReqDataWidth-1:0]    data_i,
  output logic [NumIn-1:0][RespDataWidth-1:0]   rdata_o,
  output logic [NumIn-1:0]                      vld_o,
  // slave ports
  output logic [NumOut-1:0]                     req_o,
  input  logic [NumOut-1:0]                     gnt_i,
  output logic [NumOut-1:0][$clog2(NumOut)-1:0] add_o,
  output logic [NumOut-1:0][ReqDataWidth-1:0]   data_o,
  input  logic [NumOut-1:0][RespDataWidth-1:0]  rdata_i
);

////////////////////////////////////////////////////////////////////////
// network I/O and inter-level wiring
////////////////////////////////////////////////////////////////////////
localparam int unsigned AddWidth     = $clog2(NumOut);
localparam int unsigned NumRouters   = NumOut/Radix;
localparam int unsigned NumLevels    = ($clog2(NumOut)+$clog2(Radix)-1)/$clog2(Radix);
localparam int unsigned BankFact     = NumOut/NumIn;
// check if the Radix-4 network needs a Radix-2 stage
localparam int unsigned NeedsR2Stage = ($clog2(NumOut) % 2) * int'(Radix == 4);

logic [NumLevels-1:0][NumRouters-1:0][Radix-1:0]                    router_req_in;
logic [NumLevels-1:0][NumRouters-1:0][Radix-1:0]                    router_req_out;
logic [NumLevels-1:0][NumRouters-1:0][Radix-1:0]                    router_gnt_in;
logic [NumLevels-1:0][NumRouters-1:0][Radix-1:0]                    router_gnt_out;
logic [NumLevels-1:0][NumRouters-1:0][Radix-1:0][AddWidth-1:0]      router_add_in;
logic [NumLevels-1:0][NumRouters-1:0][Radix-1:0][AddWidth-1:0]      router_add_out;
logic [NumLevels-1:0][NumRouters-1:0][Radix-1:0][ReqDataWidth-1:0]  router_data_in;
logic [NumLevels-1:0][NumRouters-1:0][Radix-1:0][ReqDataWidth-1:0]  router_data_out;
logic [NumLevels-1:0][NumRouters-1:0][Radix-1:0][RespDataWidth-1:0] router_resp_data_in;
logic [NumLevels-1:0][NumRouters-1:0][Radix-1:0][RespDataWidth-1:0] router_resp_data_out;

// // inputs are on first level
// make sure to evenly distribute masters in case of BankFactors > 1
for (genvar j = 0; unsigned'(j) < Radix*NumRouters; j++) begin : g_inputs
  // leave out input connections in interleaved way until we reach the radix
  if (BankFact < Radix) begin
    if ((j % BankFact) == 0) begin
      // req
      assign router_req_in[0][j/Radix][j%Radix]  = req_i[j/BankFact];
      assign gnt_o[j/BankFact]                   = router_gnt_out[0][j/Radix][j%Radix];
      assign router_add_in[0][j/Radix][j%Radix]  = add_i[j/BankFact];
      assign router_data_in[0][j/Radix][j%Radix] = data_i[j/BankFact];
      // resp
      assign rdata_o[j/BankFact]                 = router_resp_data_out[0][j/Radix][j%Radix];
    end else begin
      // req
      assign router_req_in[0][j/Radix][j%Radix]  = 1'b0;
      assign router_add_in[0][j/Radix][j%Radix]  = '0;
      assign router_data_in[0][j/Radix][j%Radix] = '0;
    end
  // we only enter this case if each input switchbox has 1 or zero connections
  // only connect to lower portion of switchboxes and tie off upper portion. this allows
  // us to reduce arbitration confligs on the first network layers.
  end else begin
    if(j % Radix == 0 && j/Radix < NumIn) begin
      // req
      assign router_req_in[0][j/Radix][j%Radix]  = req_i[j/Radix];
      assign gnt_o[j/Radix]                      = router_gnt_out[0][j/Radix][j%Radix];
      assign router_add_in[0][j/Radix][j%Radix]  = add_i[j/Radix];
      assign router_data_in[0][j/Radix][j%Radix] = data_i[j/Radix];
      // resp
      assign rdata_o[j/Radix]                    = router_resp_data_out[0][j/Radix][j%Radix];
    end else begin
      // req
      assign router_req_in[0][j/Radix][j%Radix]  = 1'b0;
      assign router_add_in[0][j/Radix][j%Radix]  = '0;
      assign router_data_in[0][j/Radix][j%Radix] = '0;
    end
  end
end

// outputs are on last level
for (genvar j = 0; unsigned'(j) < Radix*NumRouters; j++) begin : g_outputs
  if (j < NumOut) begin
    // req
    assign req_o[j]                                           = router_req_out[NumLevels-1][j/Radix][j%Radix];
    assign router_gnt_in[NumLevels-1][j/Radix][j%Radix]       = gnt_i[j];
    assign data_o[j]                                          = router_data_out[NumLevels-1][j/Radix][j%Radix];
    assign add_o[j]                                           = router_add_out[NumLevels-1][j/Radix][j%Radix];
    // resp
    assign router_resp_data_in[NumLevels-1][j/Radix][j%Radix] = rdata_i[j];
  end else begin
    // req
    assign router_gnt_in[NumLevels-1][j/Radix][j%Radix]       = 1'b0;
    // resp
    assign router_resp_data_in[NumLevels-1][j/Radix][j%Radix] = '0;
  end
end

// wire up connections between levels
for (genvar l = 0; unsigned'(l) < NumLevels-1; l++) begin : g_levels
  // need to add a radix-2 stage in this case
  if (l == 0 && NeedsR2Stage) begin : g_r4r2_level
    localparam int unsigned pow = 2*Radix**(NumLevels-unsigned'(l)-2);
    for (genvar r = 0; unsigned'(r) < 2*NumRouters; r++) begin : g_routers
      for (genvar s = 0; unsigned'(s) < 2; s++) begin : g_ports
        localparam int unsigned k = pow * s + (r % pow) + (r / pow / 2) * pow * 2;
        localparam int unsigned j = (r / pow) % 2;
        assign router_req_in[l+1][k/2][(k%2)*2+j]     = router_req_out[l][r/2][(r%2)*2+s];
        assign router_add_in[l+1][k/2][(k%2)*2+j]     = router_add_out[l][r/2][(r%2)*2+s];
        assign router_data_in[l+1][k/2][(k%2)*2+j]    = router_data_out[l][r/2][(r%2)*2+s];
        assign router_gnt_in[l][r/2][(r%2)*2+s]       = router_gnt_out[l+1][k/2][(k%2)*2+j];
        assign router_resp_data_in[l][r/2][(r%2)*2+s] = router_resp_data_out[l+1][k/2][(k%2)*2+j];
      end
    end
  end else begin
    localparam int unsigned pow = Radix**(NumLevels-unsigned'(l)-2);
    for (genvar r = 0; unsigned'(r) < NumRouters; r++) begin : g_routers
      for (genvar s = 0; unsigned'(s) < Radix; s++) begin : g_ports
        localparam int unsigned k = pow * s + (r % pow) + (r / pow / Radix) * pow * Radix;
        localparam int unsigned j = (r / pow) % Radix;
        assign router_req_in[l+1][k][j]     = router_req_out[l][r][s];
        assign router_add_in[l+1][k][j]     = router_add_out[l][r][s];
        assign router_data_in[l+1][k][j]    = router_data_out[l][r][s];
        assign router_gnt_in[l][r][s]       = router_gnt_out[l+1][k][j];
        assign router_resp_data_in[l][r][s] = router_resp_data_out[l+1][k][j];
      end
    end
  end
end

////////////////////////////////////////////////////////////////////////
// arbitration priorities
// we use a round robin arbiter here
////////////////////////////////////////////////////////////////////////

logic [NumIn-1:0]                                        vld_d, vld_q;
logic [$clog2(NumOut)-1:0]                               cnt_d, cnt_q;

if (ExtPrio) begin : g_ext_prio
  assign cnt_q = rr_i;
end else begin : g_no_ext_prio
  assign cnt_d = (|(gnt_i & req_o)) ? cnt_q + 1'b1 : cnt_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin : p_regs
    if (!rst_ni) begin
      cnt_q <= '0;
    end else begin
      cnt_q  <= cnt_d;
    end
  end
end

assign vld_d = gnt_o & (~wen_i | {NumIn{WriteRespOn}});
assign vld_o = vld_q;

always_ff @(posedge clk_i or negedge rst_ni) begin : p_regs
  if (!rst_ni) begin
    vld_q <= '0;
  end else begin
    vld_q  <= vld_d;
  end
end

////////////////////////////////////////////////////////////////////////
// crossbars
////////////////////////////////////////////////////////////////////////
logic [NumLevels-1:0][NumRouters-1:0][Radix-1:0][AddWidth+ReqDataWidth-1:0] data_in, data_out;

for (genvar l = 0; unsigned'(l) < NumLevels; l++) begin : g_routers1
  for (genvar r = 0; unsigned'(r) < NumRouters; r++) begin : g_routers2
    // need to add a radix-2 stage in this case
    if (l == 0 && NeedsR2Stage) begin : g_r4r2_level
      logic [NumLevels-1:0][NumRouters-1:0][Radix-1:0][0:0] add;
      logic [NumLevels-1:0][NumRouters-1:0][Radix-1:0][0:0] prio;

      for (genvar k=0; k<Radix; k++) begin : g_map
        assign add[l][r][k]  = router_add_in[l][r][k][AddWidth-1];
        assign data_in[l][r][k] = {router_add_in[l][r][k]<<1, router_data_in[l][r][k]};
        assign {router_add_out[l][r][k], router_data_out[l][r][k]} = data_out[l][r][k];
        assign prio[l][r][k] = cnt_q[$clog2(NumOut)-1];
      end

      for (genvar k=0; k<2; k++) begin : g_xbar
        xbar #(
          .NumIn         ( 2             ),
          .NumOut        ( 2             ),
          .ReqDataWidth  ( ReqDataWidth + AddWidth ),
          .RespDataWidth ( RespDataWidth ),
          .RespLat       ( RespLat       ),
          .WriteRespOn   ( 1'b0          ),
          .ExtPrio       ( 1'b1          )
        ) i_xbar (
          .clk_i   ( clk_i                                ),
          .rst_ni  ( rst_ni                               ),
          .req_i   ( router_req_in[l][r][k*2 +: 2]        ),
          .add_i   ( add[l][r][k*2 +: 2]                  ),
          .wen_i   ( '0                                   ),
          .wdata_i ( data_in[l][r][k*2 +: 2]              ),
          .gnt_o   ( router_gnt_out[l][r][k*2 +: 2]       ),
          .vld_o   (                                      ),
          .rdata_o ( router_resp_data_out[l][r][k*2 +: 2] ),
          .rr_i    ( prio[l][r][k*2 +: 2]                 ),
          .gnt_i   ( router_gnt_in[l][r][k*2 +: 2]        ),
          .req_o   ( router_req_out[l][r][k*2 +: 2]       ),
          .wdata_o ( data_out[l][r][k*2 +: 2]             ),
          .rdata_i ( router_resp_data_in[l][r][k*2 +: 2]  )
        );
      end
    // instantiate switchbox of chosen Radix
    end else begin : g_std_level
      logic [NumLevels-1:0][NumRouters-1:0][Radix-1:0][$clog2(Radix)-1:0] add;
      logic [NumLevels-1:0][NumRouters-1:0][Radix-1:0][$clog2(Radix)-1:0] prio;

      for (genvar k=0; k<Radix; k++) begin : g_map
        assign add[l][r][k]        = router_add_in[l][r][k][AddWidth-1:AddWidth-$clog2(Radix)];
        assign data_in[l][r][k]    = {router_add_in[l][r][k]<<$clog2(Radix), router_data_in[l][r][k]};
        assign {router_add_out[l][r][k], router_data_out[l][r][k]} = data_out[l][r][k];

        // depending on where the requests are connected in the radix 4 case, we have to flip the priority vector
        // this is needed because one of the bits may be constantly set to zero
        if (BankFact < Radix) begin
        // if (l==1 && NeedsR2Stage && BankFact==4 && Radix==4) begin
          for (genvar j=0; j<$clog2(Radix); j++) begin
            assign prio[l][r][k][$clog2(Radix)-1-j] = cnt_q[$clog2(NumOut)-(l+1-NeedsR2Stage)*$clog2(Radix)-NeedsR2Stage + j];
          end
        end else begin
          for (genvar j=0; j<$clog2(Radix); j++) begin
            assign prio[l][r][k][j] = cnt_q[$clog2(NumOut)-(l+1-NeedsR2Stage)*$clog2(Radix)-NeedsR2Stage + j];
          end
        end
      end

      xbar #(
        .NumIn         ( Radix         ),
        .NumOut        ( Radix         ),
        .ReqDataWidth  ( ReqDataWidth + AddWidth ),
        .RespDataWidth ( RespDataWidth ),
        .RespLat       ( RespLat       ),
        .WriteRespOn   ( 1'b0          ),
        .ExtPrio       ( 1'b1          )
      ) i_xbar (
        .clk_i   ( clk_i                      ),
        .rst_ni  ( rst_ni                     ),
        .req_i   ( router_req_in[l][r]        ),
        .add_i   ( add[l][r]                  ),
        .wen_i   ( '0                         ),
        .wdata_i ( data_in[l][r]              ),
        .gnt_o   ( router_gnt_out[l][r]       ),
        .vld_o   (                            ),
        .rdata_o ( router_resp_data_out[l][r] ),
        .rr_i    ( prio[l][r]                 ),
        .gnt_i   ( router_gnt_in[l][r]        ),
        .req_o   ( router_req_out[l][r]       ),
        .wdata_o ( data_out[l][r]             ),
        .rdata_i ( router_resp_data_in[l][r]  )
      );

    end
  end
end

////////////////////////////////////////////////////////////////////////
// assertions
////////////////////////////////////////////////////////////////////////

// pragma translate_off
initial begin
  $display("\nBfly Net info:\nNumIn=%0d\nNumOut=%0d\nBankFact=%0d\nRadix=%0d\nNeedsR2Stage=%0d\nNumRouters=%0d\nNumLevels=%0d\n",
    NumIn, NumOut, BankFact, Radix, NeedsR2Stage, NumRouters, NumLevels);

//  assert(BankFact inside {1,2,4}) else
//    $fatal(1,"Only banking factors of 1-4 are supported.");
  assert(Radix inside {2,4}) else
    $fatal(1,"Only Radix-2 and Radix-4 is supported.");
  assert(2**$clog2(NumIn) == NumIn) else
    $fatal(1,"NumIn is not aligned with a power of 2.");
  assert(2**$clog2(NumOut) == NumOut) else
    $fatal(1,"NumOut is not aligned with a power of 2.");
  assert(NumOut >= NumIn) else
    $fatal(1,"NumOut < NumIn is not supported.");
end
// pragma translate_on

endmodule // bfly_net
