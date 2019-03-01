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
  input  logic [NumIn-1:0][NumLevels-1:0]      sel_i,
  input  logic [NumIn-1:0][ReqDataWidth-1:0]   data_i,
  output logic [NumIn-1:0][RespDataWidth-1:0]  rdata_o,
  output logic [NumIn-1:0]                     rvld_o,
  // slave ports
  output logic [NumOut-1:0]                    req_o,
  input  logic [NumOut-1:0]                    gnt_i,
  output logic [NumOut-1:0][ReqDataWidth-1:0]  data_o,
  input  logic [NumOut-1:0][RespDataWidth-1:0] rdata_i
);

  localparam int unsigned LfsrTaps    = 9'b100010000;// x^9 + x^5 + 1
  localparam int unsigned LfsrWidth   = 9;
  localparam int unsigned BankingFact = NumOut/NumIn;

  logic [NumLevels-1:0][NumRouters-1:0][1:0]                    router_req_in;
  logic [NumLevels-1:0][NumRouters-1:0][1:0]                    router_req_out;
  logic [NumLevels-1:0][NumRouters-1:0][1:0]                    router_gnt_in;
  logic [NumLevels-1:0][NumRouters-1:0][1:0]                    router_gnt_out;
  logic [NumLevels-1:0][NumRouters-1:0][1:0][NumLevels-1:0]     router_sel_in;
  logic [NumLevels-1:0][NumRouters-1:0][1:0][NumLevels-1:0]     router_sel_out;
  logic [NumLevels-1:0][NumRouters-1:0][1:0][ReqDataWidth-1:0]  router_data_in;
  logic [NumLevels-1:0][NumRouters-1:0][1:0][ReqDataWidth-1:0]  router_data_out;
  logic [NumLevels-1:0][NumRouters-1:0][1:0][RespDataWidth-1:0] router_resp_data_in;
  logic [NumLevels-1:0][NumRouters-1:0][1:0][RespDataWidth-1:0] router_resp_data_out;


  logic [NumLevels-1:0][NumRouters-1:0]                         collision;
  // logic [NumLevels-1:0][NumRouters-1:0][LfsrWidth-1:0]          lfsr_d, lfsr_q;
  logic [NumLevels-1:0][NumRouters-1:0]                         router_state_d, router_state_q;
  logic [NumIn-1:0]                                             rvld_d, rvld_q;


  // inputs are on first level
  // make sure to evenly distribute masters in case of BankingFactors > 1
  for (genvar j = 0; unsigned'(j) < 2*NumRouters; j++) begin
    if(j % BankingFact == 0) begin
      // req
      assign router_req_in[0][j/2][j%2]  = req_i[j/BankingFact];
      assign gnt_o[j/BankingFact]        = router_gnt_out[0][j/2][j%2];
      assign router_sel_in[0][j/2][j%2]  = sel_i[j/BankingFact];
      assign router_data_in[0][j/2][j%2] = data_i[j/BankingFact];
      // resp
      assign rdata_o[j/BankingFact]      = router_resp_data_out[0][j/2][j%2];
    end else begin
      // req
      assign router_req_in[0][j/2][j%2]  = 1'b0;
      assign router_sel_in[0][j/2][j%2]  = '0;
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
      // just connect through output 0
      assign router_req_in[l+1][r][0]      = router_req_out[l][r][0];
      assign router_sel_in[l+1][r][0]      = router_sel_out[l][r][0];
      assign router_data_in[l+1][r][0]     = router_data_out[l][r][0];
      assign router_gnt_in[l][r][0]        = router_gnt_out[l+1][r][0];
      assign router_resp_data_in[l][r][0]  = router_resp_data_out[l+1][r][0];
      // introduce power of two jumps on output 1
      if ((r / 2**l) % 2) begin
        assign router_req_in[l+1][r - 2**l][1]  = router_req_out[l][r][1];
        assign router_sel_in[l+1][r - 2**l][1]  = router_sel_out[l][r][1];
        assign router_data_in[l+1][r - 2**l][1] = router_data_out[l][r][1];
        assign router_gnt_in[l][r][1]           = router_gnt_out[l+1][r - 2**l][1];
        assign router_resp_data_in[l][r][1]     = router_resp_data_out[l+1][r - 2**l][1];
      end else begin
        assign router_req_in[l+1][r + 2**l][1]  = router_req_out[l][r][1];
        assign router_sel_in[l+1][r + 2**l][1]  = router_sel_out[l][r][1];
        assign router_data_in[l+1][r + 2**l][1] = router_data_out[l][r][1];
        assign router_gnt_in[l][r][1]           = router_gnt_out[l+1][r + 2**l][1];
        assign router_resp_data_in[l][r][1]     = router_resp_data_out[l+1][r + 2**l][1];
      end
    end
  end

  // always_comb begin : p_lfsr
  //   lfsr_d =  lfsr_q;
  //   for (int l = 0; unsigned'(l) < NumLevels; l++)
  //     for (int r = 0; unsigned'(r) < NumRouters; r++)
  //       if (collision[l][r]) lfsr_d[l][r] = {lfsr_q[l][r][LfsrWidth-2:0], ^(lfsr_q[l][r] & LfsrTaps)};
  // end

  always_comb begin : p_router
    automatic logic sel0, sel1;
    // selection state, swap in to out mapping if 1'b1
    router_state_d  = router_state_q;
    router_gnt_out  = '0;
    collision       = '0;

    // loop over routing elements
    for (int unsigned l = 0; l < NumLevels; l++) begin
      for (int unsigned r = 0; r < NumRouters; r++) begin
        if (l == NumLevels-1) begin
          // LSB swap is done at the last stage
          sel0 = router_sel_in[l][r][0][0];
          sel1 = router_sel_in[l][r][1][0];
        end else begin
          // flip address bits in this case
          if ((r / 2**l) % 2) begin
            sel0 = ~router_sel_in[l][r][0][l+1];
            sel1 = ~router_sel_in[l][r][1][l+1];
          end else begin
            sel0 = router_sel_in[l][r][0][l+1];
            sel1 = router_sel_in[l][r][1][l+1];
          end
        end

        // propagate requests
        router_req_out[l][r][0] = (router_req_in[l][r][0] & ~sel0) |
                                  (router_req_in[l][r][1] & ~sel1);
        router_req_out[l][r][1] = (router_req_in[l][r][0] & sel0) |
                                  (router_req_in[l][r][1] & sel1);

        // routing logic
        unique casez ({~router_state_d[l][r],
                       router_req_in[l][r][0],
                       router_req_in[l][r][1],
                       sel0,
                       sel1})
          // only request from input 0
          5'b?100?: begin
            router_gnt_out[l][r][0] = router_gnt_in[l][r][0];
            router_state_d[l][r]    = 1'b0;
          end
          5'b?101?: begin
            router_gnt_out[l][r][0] = router_gnt_in[l][r][1];
            router_state_d[l][r]    = 1'b1;
          end
          // only request from input 1
          5'b?01?0: begin
            router_gnt_out[l][r][1] = router_gnt_in[l][r][0];
            router_state_d[l][r]    = 1'b1;
          end
          5'b?01?1: begin
            router_gnt_out[l][r][1] = router_gnt_in[l][r][1];
            router_state_d[l][r]    = 1'b0;
          end
          // in this case we can route both at once
          5'b?1101: begin
            router_gnt_out[l][r][0] = router_gnt_in[l][r][0];
            router_gnt_out[l][r][1] = router_gnt_in[l][r][1];
            router_state_d[l][r]    = 1'b0;
          end
          5'b?1110: begin
            router_gnt_out[l][r][0] = router_gnt_in[l][r][1];
            router_gnt_out[l][r][1] = router_gnt_in[l][r][0];
            router_state_d[l][r]    = 1'b1;
          end
          // conflicts, need to arbitrate
          5'b01100: begin
            router_gnt_out[l][r][0] = router_gnt_in[l][r][0];
            router_state_d[l][r]    = 1'b0;
            collision[l][r]         = 1'b1;
          end
          5'b01111: begin
            router_gnt_out[l][r][0] = router_gnt_in[l][r][1];
            router_state_d[l][r]    = 1'b1;
            collision[l][r]         = 1'b1;
          end
          5'b11100: begin
            router_gnt_out[l][r][1] = router_gnt_in[l][r][0];
            router_state_d[l][r]    = 1'b1;
            collision[l][r]         = 1'b1;
          end
          5'b11111: begin
            router_gnt_out[l][r][1] = router_gnt_in[l][r][1];
            router_state_d[l][r]    = 1'b0;
            collision[l][r]         = 1'b1;
          end
          default: ;
        endcase

        // data mux
        if (router_state_d[l][r]) begin
          router_sel_out[l][r][0]  = router_sel_in[l][r][1];
          router_sel_out[l][r][1]  = router_sel_in[l][r][0];
          router_data_out[l][r][0] = router_data_in[l][r][1];
          router_data_out[l][r][1] = router_data_in[l][r][0];
        end else begin
          router_sel_out[l][r][0]  = router_sel_in[l][r][0];
          router_sel_out[l][r][1]  = router_sel_in[l][r][1];
          router_data_out[l][r][0] = router_data_in[l][r][0];
          router_data_out[l][r][1] = router_data_in[l][r][1];
        end

        // resp data mux, based on previous routing state
        if (router_state_q[l][r]) begin
          router_resp_data_out[l][r][0] = router_resp_data_in[l][r][1];
          router_resp_data_out[l][r][1] = router_resp_data_in[l][r][0];
        end else begin
          router_resp_data_out[l][r][0] = router_resp_data_in[l][r][0];
          router_resp_data_out[l][r][1] = router_resp_data_in[l][r][1];
        end


      end
    end
    //////
  end

  assign rvld_d = gnt_o;
  assign rvld_o = rvld_q;

  always_ff @(posedge clk_i) begin : p_regs
    if(~rst_ni) begin
      // lfsr_q         <= '1;// do not init lfsr with 0!
      router_state_q <= '0;
      rvld_q         <= '0;
    end else begin
      // lfsr_q         <= lfsr_d;
      router_state_q <= router_state_d;
      rvld_q         <= rvld_d;
    end
  end

endmodule // rr_arb_tree