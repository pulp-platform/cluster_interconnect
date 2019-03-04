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
// Date: 01.03.2019
// Description: routing primitive for radix-2 butterfly network.

module bfly_router #(
  parameter int unsigned NumLevels     = 4,
  parameter int unsigned ReqDataWidth  = 32,
  parameter int unsigned RespDataWidth = 32
) (
  input  logic                           clk_i,
  input  logic                           rst_ni,
  // request ports
  input  logic [1:0]                     req_i,
  output logic [1:0]                     gnt_o,
  input  logic [1:0]                     sel_i,
  input  logic [1:0][NumLevels-1:0]      add_i,
  input  logic [1:0][ReqDataWidth-1:0]   data_i,
  output logic [1:0][RespDataWidth-1:0]  rdata_o,
  // target ports
  output logic [1:0]                     req_o,
  input  logic [1:0]                     gnt_i,
  output logic [1:0][NumLevels-1:0]      add_o,
  output logic [1:0][ReqDataWidth-1:0]   data_o,
  input  logic [1:0][RespDataWidth-1:0]  rdata_i
);

  logic sel_d, sel_q;

  assign add_o[0]   = (sel_d) ? add_i[1]   : add_i[0];
  assign add_o[1]   = (sel_d) ? add_i[0]   : add_i[1];
  assign data_o[0]  = (sel_d) ? data_i[1]  : data_i[0];
  assign data_o[1]  = (sel_d) ? data_i[0]  : data_i[1];
  assign gnt_o[0]   = (sel_d) ? gnt_i[1]   : gnt_i[0];
  assign gnt_o[1]   = (sel_d) ? gnt_i[0]   : gnt_i[1];
  // next cycle
  assign rdata_o[0] = (sel_q) ? rdata_i[1] : rdata_i[0];
  assign rdata_o[1] = (sel_q) ? rdata_i[0] : rdata_i[1];

  always_comb begin : p_router
    // default
    sel_d = 1'b0;

    // propagate requests
    req_o[0] = (req_i[0] & ~sel_i[0]) |
               (req_i[1] & ~sel_i[1]);
    req_o[1] = (req_i[0] & sel_i[0])  |
               (req_i[1] & sel_i[1]);

    // routing logic
    unique casez ({~sel_q,
                   req_i[0],
                   req_i[1],
                   sel_i[0],
                   sel_i[1]})
      // only request from input 0
      5'b?101?: sel_d  = 1'b1;
      // only request from input 1
      5'b?01?0: sel_d  = 1'b1;
      // in this case we can route both at once
      5'b?1110: sel_d  = 1'b1;
      // conflicts, need to arbitrate
      5'b01111: sel_d  = 1'b1;
      5'b11100: sel_d  = 1'b1;
      default: ;
    endcase
  end

  always_ff @(posedge clk_i) begin : p_regs
    if(~rst_ni) begin
      sel_q <= '0;
    end else begin
      if (|gnt_i) begin
        sel_q <= sel_d;
      end
    end
  end

endmodule // rr_arb_tree