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
// Description: logarithmic arbitration tree for TCDM with round robin arbitration.

module rr_arb_tree #(
  parameter int unsigned NumReq     = 32,
  parameter int unsigned DataWidth  = 32,
  parameter bit          SelIdxOut  = 1'b0  // outputs selected index
) (
  input  logic                             clk_i,
  input  logic                             rst_ni,
  // input requests and data
  input  logic [NumReq-1:0]                req_i,
  output logic [NumReq-1:0]                gnt_o,
  input  logic [NumReq-1:0][DataWidth-1:0] data_i,
  // arbitrated output
  input  logic                             gnt_i,
  output logic                             req_o,
  output logic [DataWidth-1:0]             data_o,
  output logic [$clog2(NumReq)-1:0]        idx_o
);

  localparam int unsigned NumLevels = $clog2(NumReq);

  logic [2**NumLevels-2:0][NumLevels-1:0]  index_nodes; // used to propagate the indices
  logic [2**NumLevels-2:0][DataWidth-1:0]  data_nodes;  // used to propagate the data
  logic [2**NumLevels-2:0]                 gnt_nodes;   // used to propagate the grant to masters
  logic [2**NumLevels-2:0]                 req_nodes;   // used to propagate the requests to slave
  logic [NumLevels-1:0]                    rr_d, rr_q;

  // the final arbitration decision can be taken from the root of the tree
  assign req_o        = (NumLevels > 0)             ? req_nodes[0]   : 1'b0;
  assign data_o       = (NumLevels > 0)             ? data_nodes[0]  : '0;
  assign idx_o        = (NumLevels > 0 & SelIdxOut) ? index_nodes[0] : '0;
  assign rr_d         = (gnt_i & req_o)             ? ((rr_q == NumReq-1) ? '0 : rr_q + 1) : rr_q;
  // assign rr_d         = (gnt_i & req_o)             ? index_nodes[0] : rr_q;
  assign gnt_nodes[0] = gnt_i;

  // arbiter tree
  for (genvar level = 0; unsigned'(level) < NumLevels; level++) begin : g_levels
    for (genvar l = 0; l < 2**level; l++) begin : g_level
      // local select signal
      logic sel;
      // index calcs
      localparam int unsigned idx0 = 2**level-1+l;// current node
      localparam int unsigned idx1 = 2**(level+1)-1+l*2;
      //////////////////////////////////////////////////////////////
      // uppermost level where data is fed in from the inputs
      if (unsigned'(level) == NumLevels-1) begin : g_first_level
        // if two successive indices are still in the vector...
        if (unsigned'(l) * 2 < NumReq-1) begin
          assign req_nodes[idx0]   = req_i[l*2] | req_i[l*2+1];

          // arbitration: round robin
          assign sel =  ~req_i[l*2] | req_i[l*2+1] & rr_q[NumLevels-1-level];

          assign index_nodes[idx0] = sel;
          assign data_nodes[idx0]  = (sel) ? data_i[l*2+1] : data_i[l*2];
          assign gnt_o[l*2]        = gnt_nodes[idx0] & req_i[l*2]   & ~sel;
          assign gnt_o[l*2+1]      = gnt_nodes[idx0] & req_i[l*2+1] & sel;
        end
        // if only the first index is still in the vector...
        if (unsigned'(l) * 2 == NumReq-1) begin
          assign req_nodes[idx0]   = req_i[l*2];
          assign index_nodes[idx0] = '0;// always zero in this case
          assign data_nodes[idx0]  = data_i[l*2];
          assign gnt_o[l*2]        = gnt_nodes[idx0] & req_i[l*2];
        end
        // if index is out of range, fill up with zeros (will get pruned)
        if (unsigned'(l) * 2 > NumReq-1) begin
          assign req_nodes[idx0]   = 1'b0;
          assign index_nodes[idx0] = '0;
          assign data_nodes[idx0]  = '0;
        end
      //////////////////////////////////////////////////////////////
      // general case for other levels within the tree
      end else begin : g_other_levels
        assign req_nodes[idx0]   = req_nodes[idx1] | req_nodes[idx1+1];

        // arbitration: round robin
        assign sel =  ~req_nodes[idx1] | req_nodes[idx1+1] & rr_q[NumLevels-1-level];

        assign index_nodes[idx0] = (sel) ? {1'b1, index_nodes[idx1+1][NumLevels-level-2:0]} : {1'b0, index_nodes[idx1][NumLevels-level-2:0]};
        assign data_nodes[idx0]  = (sel) ? data_nodes[idx1+1] : data_nodes[idx1];
        assign gnt_nodes[idx1]   = gnt_nodes[idx0] & ~sel;
        assign gnt_nodes[idx1+1] = gnt_nodes[idx0] & sel;
      end
      //////////////////////////////////////////////////////////////
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : p_regs
    if(~rst_ni) begin
      rr_q <= '0;
    end else begin
      rr_q <= rr_d;
    end
  end

endmodule // rr_arb_tree