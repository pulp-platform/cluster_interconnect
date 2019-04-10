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
// Description: Routing primitive for radix-2 butterfly network.

module bfly_router #(
  parameter int unsigned AddWidth      = 4,
  parameter int unsigned ReqDataWidth  = 32,
  parameter int unsigned RespDataWidth = 32,
  // redundant layers do not route according to address,
  // but just use the prio to select an output
  parameter bit unsigned IsRedundant   = 0,
  // in case of broadcast, all free outputs are
  // used to place arequest if this router is on a
  // redundant layer
  parameter bit unsigned BroadCastOn   = 0
) (
  input  logic                           clk_i,
  input  logic                           rst_ni,
  // request ports
  input  logic [1:0]                     req_i,
  output logic [1:0]                     gnt_o,
  input  logic                           prio_i,
  input  logic [1:0][AddWidth-1:0]       add_i,
  input  logic [1:0][ReqDataWidth-1:0]   data_i,
  output logic [1:0][RespDataWidth-1:0]  rdata_o,
  // target ports
  output logic [1:0]                     req_o,
  input  logic [1:0]                     gnt_i,
  output logic [1:0][AddWidth-1:0]       add_o,
  output logic [1:0][ReqDataWidth-1:0]   data_o,
  input  logic [1:0][RespDataWidth-1:0]  rdata_i
);

  logic bcast;
  logic sel_d, sel_q;

	if (IsRedundant) begin
		// leave routing address unchanged in this case
    assign add_o[0]   = (sel_d)       ? add_i[1]    : add_i[0];
    assign add_o[1]   = (sel_d^bcast) ? add_i[0]    : add_i[1];
    assign data_o[0]  = (sel_d)       ? data_i[1]   : data_i[0];
    assign data_o[1]  = (sel_d^bcast) ? data_i[0]   : data_i[1];
    assign gnt_o[0]   = (sel_d)       ? gnt_i[1] & ~bcast           : gnt_i[0] | gnt_i[1] & bcast;
    assign gnt_o[1]   = (sel_d)       ? gnt_i[0] | gnt_i[1] & bcast : gnt_i[1] & ~bcast;
  end else begin
    // if this is not a redundant layer
    // shift addr bits as we progress through the network layers
    // the first layer uses the MSB and the last layer the LSB for routing
    assign add_o[0]   = (sel_d) ? add_i[1]<<1 : add_i[0]<<1;
	  assign add_o[1]   = (sel_d) ? add_i[0]<<1 : add_i[1]<<1;
	  assign data_o[0]  = (sel_d) ? data_i[1]   : data_i[0];
    assign data_o[1]  = (sel_d) ? data_i[0]   : data_i[1];
    assign gnt_o[0]   = (sel_d) ? gnt_i[1]    : gnt_i[0];
    assign gnt_o[1]   = (sel_d) ? gnt_i[0]    : gnt_i[1];
  end

  // next cycle
  assign rdata_o[0] = (sel_q) ? rdata_i[1] : rdata_i[0];
  assign rdata_o[1] = (sel_q) ? rdata_i[0] : rdata_i[1];

	always_comb begin : p_router
    // default
    bcast = 1'b0;
    sel_d = 1'b0;
  	if (IsRedundant) begin
      if (BroadCastOn) begin
        // in case of broadcast always request on all req ports,
        // and in case of a tie use external prio signal to resolve
        req_o[0]    = req_i[0] | req_i[1];
        req_o[1]    = req_i[0] | req_i[1];
        unique casez ({prio_i,
                       req_i[0],
                       req_i[1]})
          // only request from input 0
          3'b?10: begin
            bcast  = 1'b1;;
            sel_d = 1'b0;
          end
          // only request from input 1
          3'b?01: begin
            bcast  = 1'b1;
            sel_d  = 1'b1;
          end
          // conflicts, need to arbitrate
          3'b?11: begin
            bcast  = 1'b0;
            sel_d  = prio_i;
          end
          default: ;
        endcase
      end else begin
        sel_d       = prio_i;
        req_o[0]    = (prio_i) ? req_i[1] : req_i[0];
        req_o[1]    = (prio_i) ? req_i[0] : req_i[1];
      end
    end else begin
	    // propagate requests
	    req_o[0] = (req_i[0] & ~add_i[0][AddWidth-1]) |
	               (req_i[1] & ~add_i[1][AddWidth-1]);
	    req_o[1] = (req_i[0] & add_i[0][AddWidth-1])  |
	               (req_i[1] & add_i[1][AddWidth-1]);

	    // arbiter logic
	    unique casez ({prio_i,
	                   req_i[0],
	                   req_i[1],
	                   add_i[0][AddWidth-1],
	                   add_i[1][AddWidth-1]})
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
  end

 	always_ff @(posedge clk_i or negedge rst_ni) begin : p_regs1
	  if(~rst_ni) begin
	  	sel_q   <= '0;
	  end else begin
	   	if (|req_i) begin
        if (bcast) begin
	    	  sel_q   <= sel_d ^ gnt_i[1];
        end else begin
          sel_q   <= sel_d;
        end
	    end
	  end
	end

endmodule // rr_arb_tree