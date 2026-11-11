// Copyright 2020 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Author: Michael Schaffner <schaffner@iis.ee.ethz.ch>, ETH Zurich
//         Matheus Cavalcante <matheusd@iis.ee.ethz.ch>, ETH Zurich
//         Marco Bertuletti <mbertuletti@iis.ee.ethz.ch>, ETH Zurich

// Date: 16.01.2020

// Description: Interconnect with support to variable target latencies with different
// network topologies. Currently supported are: full crossbar and radix-2/4 butterflies.
// Note that only the full crossbar allows NumIn/NumOut configurations that are not
// aligned to a power of 2.

module burst_variable_latency_interconnect import tcdm_interconnect_pkg::topo_e; #(
  // Global parameters
  parameter int unsigned NumIn             = 32,                    // Number of Initiators. Must be aligned with a power of 2 for butterflies.
  parameter int unsigned NumOut            = 64,                    // Number of Targets. Must be aligned with a power of 2 for butterflies.
  parameter int unsigned AddrWidth         = 32,                    // Address Width on the Initiator Side
  parameter int unsigned DataWidth         = 32,                    // Data Word Width
  parameter int unsigned BeWidth           = DataWidth/8,           // Byte Strobe Width
  parameter int unsigned AddrMemWidth      = 12,                    // Number of Address bits per Target
  parameter int unsigned BurstWidth        = 1,                     // Burst Signal Width
  parameter int unsigned BurstRspWidth     = 1,                     // Burst Response Widening
  parameter bit AxiVldRdy                  = 1'b1,                  // Valid/ready signaling
  // Spill registers
  // A bit set at position i indicates a spill register at the i-th crossbar layer.
  // The layers are counted starting at 0 from the initiator, for the requests, and from the target, for the responses.
  parameter logic [63:0] SpillRegisterReq  = 64'h0,
  parameter logic [63:0] SpillRegisterResp = 64'h0,
  parameter bit FallThroughRegister        = 1'b0,                  // Insert a fall-through register, if missing a spill register in that stage
  // Determines the width of the byte offset in a memory word. Normally this can be left at the default value,
  // but sometimes it needs to be overridden (e.g., when metadata is supplied to the memory via the wdata signal).
  parameter int unsigned ByteOffWidth      = $clog2(DataWidth-1)-3,
  // Topology can be: LIC, BFLY2, BFLY4, CLOS
  parameter topo_e Topology = tcdm_interconnect_pkg::LIC,
  // Dependant parameters. DO NOT CHANGE!
  parameter int unsigned NumInLog2         = NumIn == 1 ? 1 : $clog2(NumIn)
) (
  input  logic clk_i,
  input  logic rst_ni,
  // Initiator side
  input  logic [NumIn-1:0]                     req_valid_i,     // Request valid
  output logic [NumIn-1:0]                     req_ready_o,     // Request ready
  input  logic [NumIn-1:0][AddrWidth-1:0]      req_tgt_addr_i,  // Target address
  input  logic [NumIn-1:0]                     req_wen_i,       // Write enable
  input  logic [NumIn-1:0][DataWidth-1:0]      req_wdata_i,     // Write data
  input  logic [NumIn-1:0][BeWidth-1:0]        req_be_i,        // Byte enable
  input  logic [NumIn-1:0][BurstWidth-1:0]     req_burst_i,     // Burst data
  output logic [NumIn-1:0]                     resp_valid_o,    // Response valid
  input  logic [NumIn-1:0]                     resp_ready_i,    // Response ready
  output logic [NumIn-1:0][DataWidth-1:0]      resp_rdata_o,    // Data response
  output logic [NumIn-1:0][BurstRspWidth-1:0]  resp_burst_o,    // Burst response
  // Target side
  output logic [NumOut-1:0]                    req_valid_o,     // Request valid
  input  logic [NumOut-1:0]                    req_ready_i,     // Request ready
  output logic [NumOut-1:0][NumInLog2-1:0]     req_ini_addr_o,  // Initiator address
  output logic [NumOut-1:0][AddrMemWidth-1:0]  req_tgt_addr_o,  // Target address
  output logic [NumOut-1:0]                    req_wen_o,       // Write enable
  output logic [NumOut-1:0][DataWidth-1:0]     req_wdata_o,     // Write data
  output logic [NumOut-1:0][BeWidth-1:0]       req_be_o,        // Byte enable
  output logic [NumOut-1:0][BurstWidth-1:0]    req_burst_o,     // Burst data
  input  logic [NumOut-1:0]                    resp_valid_i,    // Response valid
  output logic [NumOut-1:0]                    resp_ready_o,    // Response ready
  input  logic [NumOut-1:0][NumInLog2-1:0]     resp_ini_addr_i, // Initiator address
  input  logic [NumOut-1:0][DataWidth-1:0]     resp_rdata_i,    // Data response
  input  logic [NumOut-1:0][BurstRspWidth-1:0] resp_burst_i     // Burst response
);

  localparam int unsigned ReqAggDataWidth = DataWidth + BurstWidth;
  localparam int unsigned RespAggDataWidth = DataWidth + BurstRspWidth;

  logic [NumIn-1:0][ReqAggDataWidth-1:0]  req_agg_data_in;
  logic [NumOut-1:0][ReqAggDataWidth-1:0] req_agg_data_out;

  logic [NumIn-1:0][RespAggDataWidth-1:0]  resp_agg_data_out;
  logic [NumOut-1:0][RespAggDataWidth-1:0] resp_agg_data_in;

  for (genvar j = 0; unsigned'(j) < NumIn; j++) begin : gen_inputs
    assign req_agg_data_in[j] = {req_wdata_i[j], req_burst_i[j]};
    assign {resp_rdata_o[j], resp_burst_o[j]} = resp_agg_data_out[j];
  end

  for (genvar k = 0; unsigned'(k) < NumOut; k++) begin : gen_outputs
    assign {req_wdata_o[k], req_burst_o[k]} = req_agg_data_out[k];
    assign resp_agg_data_in[k] = {resp_rdata_i[k], resp_burst_i[k]};
  end

  variable_latency_interconnect #(
    .NumIn               (NumIn               ),
    .NumOut              (NumOut              ),
    .AddrWidth           (AddrWidth           ),
    .ReqDataWidth        (ReqAggDataWidth     ),
    .RespDataWidth       (RespAggDataWidth    ),
    .BeWidth             (BeWidth             ),
    .AddrMemWidth        (AddrMemWidth        ),
    .AxiVldRdy           (AxiVldRdy           ),
    .SpillRegisterReq    (SpillRegisterReq    ),
    .SpillRegisterResp   (SpillRegisterResp   ),
    .FallThroughRegister (FallThroughRegister ),
    .ByteOffWidth        (ByteOffWidth        ),
    .Topology            (Topology            )
  ) i_variable_latency_interconnect (
    .clk_i,
    .rst_ni,
    .req_valid_i     (req_valid_i       ),
    .req_ready_o     (req_ready_o       ),
    .req_tgt_addr_i  (req_tgt_addr_i    ),
    .req_wen_i       (req_wen_i         ),
    .req_wdata_i     (req_agg_data_in   ),
    .req_be_i        (req_be_i          ),
    .resp_valid_o    (resp_valid_o      ),
    .resp_ready_i    (resp_ready_i      ),
    .resp_rdata_o    (resp_agg_data_out ),
    // Target side
    .req_valid_o     (req_valid_o       ),
    .req_ready_i     (req_ready_i       ),
    .req_ini_addr_o  (req_ini_addr_o    ),
    .req_tgt_addr_o  (req_tgt_addr_o    ),
    .req_wen_o       (req_wen_o         ),
    .req_wdata_o     (req_agg_data_out  ),
    .req_be_o        (req_be_o          ),
    .resp_valid_i    (resp_valid_i      ),
    .resp_ready_o    (resp_ready_o      ),
    .resp_ini_addr_i (resp_ini_addr_i   ),
    .resp_rdata_i    (resp_agg_data_in  )
  );

endmodule : burst_variable_latency_interconnect
