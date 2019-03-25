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
	// make sure NumIn and NumOut are aligned to powers of two at the moment
  parameter int unsigned NumIn           = 64,           // number of initiator ports
  parameter int unsigned NumOut          = 256,          // number of TCDM banks
  parameter int unsigned AddrWidth       = 32,           // address width on initiator side
  parameter int unsigned DataWidth       = 32,           // word width of data
  parameter int unsigned BeWidth         = DataWidth/8,  // width of corresponding byte enables
  parameter int unsigned AddrMemWidth    = 12,           // number of address bits per TCDM bank
  parameter int unsigned Topology        = 2,            // 0 = lic, 1 = radix-2 bfly, 2 = clos
	parameter bit          WriteRespOn     = 1,            // defines whether the interconnect returns a write response
  // TCDM read latency, usually 1 cycle
  // has no effect on butterfly topology (fixed to 1 in that case)
  parameter int unsigned MemLatency      = 1,
  // butterfly parameters
  // redundant stages are not fully supported yet
  parameter int unsigned RedundantStages = 0,
  // classic clos parameters, make sure they are aligned with powers of 2
  // good tradeoff in terms of router complexity (when M=2N):  N = sqrt(NumOut / 2)
  // some values:
  // 8  Banks -> N = 2,
  // 16 Banks -> N = 4,
  // 32 Banks -> N = 4,
  // 64 Banks -> N = 8,
  // 128 Banks -> N = 8,
  // 256 Banks -> N = 16,
  // 512 Banks -> N = 16
  parameter real ClosRedFact             = 2.0,
  parameter int unsigned ClosN           = 2**$clog2((NumOut / 2)>>1),
  // number of middle stage switches setting to 2*N/BankingFactor guarantees no collisions with optimum routing
  parameter int unsigned ClosM           = int'(ClosRedFact*real'(ClosN)),
  // determined by number of outputs and N
  parameter int unsigned ClosR           = 2**$clog2(NumOut / ClosN)

) (
  input  logic                                  clk_i,
  input  logic                                  rst_ni,
  // master side
  input  logic [NumIn-1:0]                      req_i,     // Request signal
  input  logic [NumIn-1:0][AddrWidth-1:0]       add_i,     // Address
  input  logic [NumIn-1:0]                      wen_i,     // 1: Store, 0: Load
  input  logic [NumIn-1:0][DataWidth-1:0]       wdata_i,   // Write data
  input  logic [NumIn-1:0][BeWidth-1:0]         be_i,      // Byte enable
  output logic [NumIn-1:0]                      gnt_o,     // Grant (combinationally dependent on req_i and add_i)
  output logic [NumIn-1:0]                      vld_o,     // Response valid, also asserted if write responses are enabled
  output logic [NumIn-1:0][DataWidth-1:0]       rdata_o,   // Data Response DATA (For LOAD commands)
  // slave side
  output  logic [NumOut-1:0]                    req_o,     // Bank request
  input   logic [NumOut-1:0]                    gnt_i,     // Bank grant
  output  logic [NumOut-1:0][AddrMemWidth-1:0]  add_o,     // Address
  output  logic [NumOut-1:0]                    wen_o,     // 1: Store, 0: Load
  output  logic [NumOut-1:0][DataWidth-1:0]     wdata_o,   // Write data
  output  logic [NumOut-1:0][BeWidth-1:0]       be_o,      // Byte enable
  input   logic [NumOut-1:0][DataWidth-1:0]     rdata_i    // Read data
);

  localparam int unsigned BandAddWidth  = $clog2(NumOut);
  localparam int unsigned AddrWordOff   = $clog2(DataWidth-1)-3;
  localparam int unsigned AggDataWidth  = 1+BeWidth+AddrMemWidth+DataWidth;
  logic [NumIn-1:0][AggDataWidth-1:0]  data_agg_in;
  logic [NumOut-1:0][AggDataWidth-1:0] data_agg_out;
  logic [NumIn-1:0][BandAddWidth-1:0] bank_sel;

  for (genvar j=0; unsigned'(j)<NumIn; j++) begin : g_inputs
    // extract bank index
    assign bank_sel[j] = add_i[j][AddrWordOff+BandAddWidth-1:AddrWordOff];
    // aggregate data to be routed to slaves
    assign data_agg_in[j] = {wen_i[j], be_i[j], add_i[j][AddrWordOff+BandAddWidth+AddrMemWidth-1:AddrWordOff+BandAddWidth], wdata_i[j]};
  end

  // disaggregate data
  for (genvar k=0; unsigned'(k)<NumOut; k++) begin : g_outputs
    assign {wen_o[k], be_o[k], add_o[k], wdata_o[k]} = data_agg_out[k];
  end

  /////////////////////////////////////////////////////////////////////
  // tuned logarithmic interconnect architecture, based on rr_arb_tree primitives
  if (Topology==0) begin : g_lic
    clos_node #(
      .NumIn         ( NumIn        ),
      .NumOut        ( NumOut       ),
      .ReqDataWidth  ( AggDataWidth ),
      .RespDataWidth ( DataWidth    ),
      .WriteRespOn   ( WriteRespOn  ),
      .MemLatency    ( MemLatency   ),
      .NodeType      ( 1            ) // clos middle node is a full lic crossbar
    ) i_clos_node (
      .clk_i   ( clk_i        ),
      .rst_ni  ( rst_ni       ),
      .req_i   ( req_i        ),
      .add_i   ( bank_sel     ),
      .wen_i   ( wen_i        ),
      .wdata_i ( data_agg_in  ),
      .gnt_o   ( gnt_o        ),
      .rdata_o ( rdata_o      ),
      .vld_o   ( vld_o        ),
      .gnt_i   ( gnt_i        ),
      .req_o   ( req_o        ),
      .wdata_o ( data_agg_out ),
      .rdata_i ( rdata_i      )
    );
  /////////////////////////////////////////////////////////////////////
  // scalable interconnect using a (redundant) butterfly network
  end else if (Topology==1) begin : g_bfly

    if (RedundantStages>0) begin : g_redundant
      logic [NumOut-1:0][AggDataWidth-1:0]  bfly_wdata;
      logic [NumOut-1:0][DataWidth-1:0]     bfly_rdata;
      logic [NumOut-1:0][BandAddWidth-1:0] bfly_bank;
      logic [NumOut-1:0]  bfly_req, bfly_gnt;

      // redundant stage
      bfly_net #(
        .NumIn           ( NumIn           ),
        .NumOut          ( NumOut          ),
        .ReqDataWidth    ( AggDataWidth    ),
        .RespDataWidth   ( DataWidth       ),
        .WriteRespOn     ( WriteRespOn     ),
        .RedundantStages ( RedundantStages )
      ) i_bfly_net_red (
        .clk_i    ( clk_i        ),
        .rst_ni   ( rst_ni       ),
        .req_i    ( req_i        ),
        .gnt_o    ( gnt_o        ),
        .add_i    ( bank_sel     ),
        .wen_i    ( wen_i        ),
        .data_i   ( data_agg_in  ),
        .rdata_o  ( rdata_o      ),
        .vld_o    ( vld_o        ),
        .req_o    ( bfly_req     ),
        .gnt_i    ( bfly_gnt     ), 
        .add_o    ( bfly_bank    ),
        .data_o   ( bfly_wdata   ),
        .rdata_i  ( bfly_rdata   )
      );

      bfly_net #(
        .NumIn         ( NumOut       ),
        .NumOut        ( NumOut       ),
        .ReqDataWidth  ( AggDataWidth ),
        .RespDataWidth ( DataWidth    )
      ) i_bfly_net (
        .clk_i    ( clk_i        ),
        .rst_ni   ( rst_ni       ),
        .req_i    ( bfly_req     ),
        .gnt_o    ( bfly_gnt     ),
        .add_i    ( bfly_bank    ),
        .wen_i    ( '0           ),
        .data_i   ( bfly_wdata   ),
        .rdata_o  ( bfly_rdata   ),
        .vld_o    (              ),
        .req_o    ( req_o        ),
        .gnt_i    ( gnt_i        ), 
        .add_o    (              ),
        .data_o   ( data_agg_out ),
        .rdata_i  ( rdata_i      )
      );
    end else begin : g_normal
      bfly_net #(
        .NumIn         ( NumIn        ),
        .NumOut        ( NumOut       ),
        .ReqDataWidth  ( AggDataWidth ),
        .RespDataWidth ( DataWidth    ),
        .WriteRespOn   ( WriteRespOn  )
      ) i_bfly_net (
        .clk_i    ( clk_i        ),
        .rst_ni   ( rst_ni       ),
        .req_i    ( req_i        ),
        .gnt_o    ( gnt_o        ),
        .add_i    ( bank_sel     ),
        .wen_i    ( wen_i        ),
        .data_i   ( data_agg_in  ),
        .rdata_o  ( rdata_o      ),
        .vld_o    ( vld_o        ),
        .req_o    ( req_o        ),
        .gnt_i    ( gnt_i        ), 
        .add_o    (              ),
        .data_o   ( data_agg_out ),
        .rdata_i  ( rdata_i      )
      );
    end
  /////////////////////////////////////////////////////////////////////
  // optimum collision free clos (m=n) with optimum router
  // size (aligned to powers of 2)
  end else if (Topology==2) begin : g_clos
    clos_net #(
      .NumIn         ( NumIn        ),
      .NumOut        ( NumOut       ),
      .ReqDataWidth  ( AggDataWidth ),
      .RespDataWidth ( DataWidth    ),
      .WriteRespOn   ( WriteRespOn  ),
      .ClosN         ( ClosN        ),
      .ClosM         ( ClosM        ),
      .ClosR         ( ClosR        )
    ) i_clos_net (
      .clk_i    ( clk_i        ),
      .rst_ni   ( rst_ni       ),
      .req_i    ( req_i        ),
      .gnt_o    ( gnt_o        ),
      .add_i    ( bank_sel     ),
      .wen_i    ( wen_i        ),
      .wdata_i  ( data_agg_in  ),
      .rdata_o  ( rdata_o      ),
      .vld_o    ( vld_o        ),
      .req_o    ( req_o        ),
      .gnt_i    ( gnt_i        ), 
      .wdata_o  ( data_agg_out ),
      .rdata_i  ( rdata_i      )
    );
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
  	$display("Clos configuration: NumIn: %d, NumOut: %d, m=%d, n=%d, r=%d", NumIn, NumOut, ClosM, ClosN, ClosR);
    assert(AddrMemWidth+BandAddWidth+AddrMemWidth <= AddrWidth) else
      $fatal(1,"Address not wide enough to accomodate the requested TCDM configuration.");
    assert(2**$clog2(NumIn) == NumIn) else
      $fatal(1,"NumIn is not aligned with a power of 2.");
    assert(2**$clog2(NumOut) == NumOut) else
      $fatal(1,"NumOut is not aligned with a power of 2.");
  end
  // pragma translate_on

endmodule
