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
// Description: address decoder and response mux for TCDM.

module addr_dec_resp_mux #(
    parameter int unsigned NumSlave      = 32,
    parameter int unsigned ReqDataWidth  = 32,
    parameter int unsigned RespDataWidth = 32,
    parameter int unsigned RespLat       = 1   // read latency of slaves
) (
  input  logic                                    clk_i,
  input  logic                                    rst_ni,
  // master side
  input  logic                                    req_i,    // request from this master
  input  logic [$clog2(NumSlave)-1:0]             add_i,    // bank selection index to be decoded
  input  logic [ReqDataWidth-1:0]                 data_i,   // data to be transported to slaves
  output logic                                    gnt_o,    // grant to master
  output logic                                    rvld_o,   // read response is valid
  output logic [RespDataWidth-1:0]                rdata_o,  // read response
  // slave side
  output logic [NumSlave-1:0]                     req_o,    // request signals after decoding
  input  logic [NumSlave-1:0]                     gnt_i,    // grants from slaves
  output logic [NumSlave-1:0][ReqDataWidth-1:0]   data_o,   // data to be transported to slaves
  input  logic [NumSlave-1:0][RespDataWidth-1:0]  rdata_i   // read responses from slaves
);

logic [RespLat-1:0][$clog2(NumSlave)-1:0] bank_sel_d, bank_sel_q;
logic [RespLat-1:0]                       vld_d, vld_q;

// address decoder
always_comb begin : p_addr_dec
  req_o        = '0;
  req_o[add_i] = req_i;
end

// connect data outputs
assign data_o = {NumSlave{data_i}};

// aggregate grant signals
assign gnt_o = |gnt_i;

if (RespLat > 1) begin
  assign bank_sel_d = {bank_sel_q[$high(bank_sel_q)-1:0], add_i};
  assign vld_d      = {vld_q[$high(vld_q)-1:0], gnt_o};
end else begin
  assign bank_sel_d = add_i;
  assign vld_d      = gnt_o;
end

assign rdata_o = rdata_i[bank_sel_q[$high(bank_sel_q)]];
assign rvld_o  = vld_q[$high(vld_q)];

always_ff @(posedge clk_i or negedge rst_ni) begin : p_reg
  if(~rst_ni) begin
    bank_sel_q <= '0;
    vld_q      <= '0;
  end else begin
    bank_sel_q <= bank_sel_d;
    vld_q      <= vld_d;
  end
end

endmodule // addr_dec_resp_mux