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
// Description: TCDM interconnect with different network topologies 
// (logarithmic interconnect and radix-2 butterflies)

module tcdm_interconnect #(
	// make sure NumMaster and NumSlave are aligned to powers of two at the moment
  parameter int unsigned NumMaster       = 128,          // number of initiator ports
  parameter int unsigned NumSlave        = 256,          // number of TCDM banks
  parameter int unsigned AddrWidth       = 32,           // address width on initiator side
  parameter int unsigned DataWidth       = 32,           // word width of data
  parameter int unsigned BeWidth         = DataWidth/8,  // width of corresponding byte enables
  parameter int unsigned AddrMemWidth    = 12,           // number of address bits per TCDM bank
  parameter int unsigned Topology        = 0,            // 0 = lic, 1 = bfly
	// TCDM read latency, usually 1 cycle
  // has no effect on butterfly topology (fixed to 1 in that case)
  parameter int unsigned MemLatency      = 1,            
  // redundant stages are not fully supported yet
  parameter int unsigned RedundantStages = 0             // number of redundant butterfly stages
) (
  input  logic                                    clk_i,
  input  logic                                    rst_ni,
  // master side
  input  logic [NumMaster-1:0]                    req_i,     // Request signal
  input  logic [NumMaster-1:0][AddrWidth-1:0]     add_i,     // Address
  input  logic [NumMaster-1:0]                    wen_i,     // 0--> Store, 1 --> Load
  input  logic [NumMaster-1:0][DataWidth-1:0]     wdata_i,   // Write data
  input  logic [NumMaster-1:0][BeWidth-1:0]       be_i,      // Byte enable
  output logic [NumMaster-1:0]                    gnt_o,     // Grant (combinationally dependent on req_i and add_i)
  output logic [NumMaster-1:0]                    rvld_o,    // Response valid
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

  for (genvar j=0; unsigned'(j)<NumMaster; j++) begin : g_inputs
    // extract bank index
    assign bank_sel[j] = add_i[j][AddrWordOff+SlaveSelWidth-1:AddrWordOff];
    // aggregate data to be routed to slaves
    assign data_agg_in[j] = {wen_i[j], be_i[j], add_i[j][AddrWordOff+SlaveSelWidth+AddrMemWidth-1:AddrWordOff+SlaveSelWidth], wdata_i[j]};
  end

  // disaggregate data
  for (genvar k=0; unsigned'(k)<NumSlave; k++) begin : g_outputs
    assign {wen_o[k], be_o[k], add_o[k], wdata_o[k]} = data_agg_out[k];
  end

  /////////////////////////////////////////////////////////////////////
  // tuned logarithmic interconnect architecture, based on rr_arb_tree primitives
  if (Topology==0) begin : g_lic

    logic [NumSlave-1:0][NumMaster-1:0][AggDataWidth-1:0]  sl_data;
    logic [NumMaster-1:0][NumSlave-1:0][AggDataWidth-1:0]  ma_data;
    logic [NumSlave-1:0][NumMaster-1:0] sl_gnt, sl_req;
    logic [NumMaster-1:0][NumSlave-1:0] ma_gnt, ma_req;

    // loop over slaves (endpoints)
    // instantiate an RR arbiter for each endpoint
    for (genvar k=0; unsigned'(k)<NumSlave; k++) begin : g_masters
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
        .idx_o  (                 )// disabled
      );
    end

    // loop over masters and instantiate bank address decoder/resp mux for each master
    for (genvar j=0; unsigned'(j)<NumMaster; j++) begin : g_slaves
      addr_dec_resp_mux #(
        .NumSlave      ( NumSlave     ),
        .ReqDataWidth  ( AggDataWidth ),
        .RespDataWidth ( DataWidth    ),
        .RespLat       ( MemLatency   )
      ) i_addr_dec_resp_mux (
        .clk_i  ( clk_i          ),
        .rst_ni ( rst_ni         ),
        .req_i  ( req_i[j]       ),
        .add_i  ( bank_sel[j]    ),
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
      for (genvar k=0; unsigned'(k)<NumSlave; k++) begin : g_reshape
        assign sl_req[k][j]  = ma_req[j][k];
        assign ma_gnt[j][k]  = sl_gnt[k][j];
        assign sl_data[k][j] = ma_data[j][k];
      end
    end
  /////////////////////////////////////////////////////////////////////
  // scalable interconnect using a (redundant) butterfly network
  end else if (Topology==1) begin : g_bfly

  	if (RedundantStages>0) begin : g_redundant
	  	logic [NumSlave-1:0][AggDataWidth-1:0]  bfly_wdata;
	  	logic [NumSlave-1:0][DataWidth-1:0]     bfly_rdata;
			logic [NumSlave-1:0][SlaveSelWidth-1:0] bfly_bank;
			logic [NumSlave-1:0]  bfly_req, bfly_gnt;

	  	// redundant stage
	    bfly_net #(
	      .NumIn(NumMaster),
	      .NumOut(NumSlave),
	      .ReqDataWidth(AggDataWidth),
	      .RespDataWidth(DataWidth),
	      .RedundantStages(RedundantStages)
	    ) i_bfly_net_red (
	      .clk_i    ( clk_i        ),
	      .rst_ni   ( rst_ni       ),
	      .req_i    ( req_i        ),
	      .gnt_o    ( gnt_o        ),
	      .add_i    ( bank_sel     ),
	      .data_i   ( data_agg_in  ),
	      .rdata_o  ( rdata_o      ),
	      .rvld_o   ( rvld_o       ),
	      .req_o    ( bfly_req     ),
	      .gnt_i    ( bfly_gnt     ), // TCDM is always ready
	      .add_o    ( bfly_bank    ),
	      .data_o   ( bfly_wdata   ),
	      .rdata_i  ( bfly_rdata   )
	    );  	

	    bfly_net #(
	      .NumIn(NumSlave),
	      .NumOut(NumSlave),
	      .ReqDataWidth(AggDataWidth),
	      .RespDataWidth(DataWidth)
	    ) i_bfly_net (
	      .clk_i    ( clk_i        ),
	      .rst_ni   ( rst_ni       ),
	      .req_i    ( bfly_req     ),
	      .gnt_o    ( bfly_gnt     ),
	      .add_i    ( bfly_bank    ),
	      .data_i   ( bfly_wdata   ),
	      .rdata_o  ( bfly_rdata   ),
	      .rvld_o   (              ),
	      .req_o    ( cs_o         ),
	      .gnt_i    ( cs_o         ), // TCDM is always ready
	      .add_o    (              ),
	      .data_o   ( data_agg_out ),
	      .rdata_i  ( rdata_i      )
	    );
	  end	else begin : g_normal
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
	      .add_i    ( bank_sel     ),
	      .data_i   ( data_agg_in  ),
	      .rdata_o  ( rdata_o      ),
	      .rvld_o   ( rvld_o       ),
	      .req_o    ( cs_o         ),
	      .gnt_i    ( cs_o         ), // TCDM is always ready
	      .add_o    (              ),
	      .data_o   ( data_agg_out ),
	      .rdata_i  ( rdata_i      )
	    );
	  end  
  /////////////////////////////////////////////////////////////////////
  end else begin : g_unknown
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
    assert(2**$clog2(NumMaster) == NumMaster) else
      $fatal(1,"NumMaster is not aligned with a power of 2.");
    assert(2**$clog2(NumSlave) == NumSlave) else
      $fatal(1,"NumSlave is not aligned with a power of 2.");
  end
  // pragma translate_on

endmodule
