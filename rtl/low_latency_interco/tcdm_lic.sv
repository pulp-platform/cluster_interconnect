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
// Description: logarithmic interconnect for TCDM.

module tcdm_lic #(
    parameter N_MASTER        = 16, 
    parameter N_SLAVE         = 32,
    parameter ADDR_WIDTH      = 32,
    parameter DATA_WIDTH      = 32,
    parameter BE_WIDTH        = DATA_WIDTH/8,
    parameter ADDR_MEM_WIDTH  = 12
) (
    input  logic                                    clk_i,
    input  logic                                    rst_ni,
    // master side
    input  logic [N_MASTER-1:0]                     data_req_i,            // Data request
    input  logic [N_MASTER-1:0][ADDR_WIDTH-1:0]     data_add_i,            // Data request Address
    input  logic [N_MASTER-1:0]                     data_wen_i,            // Data request type : 0--> Store, 1 --> Load
    input  logic [N_MASTER-1:0][DATA_WIDTH-1:0]     data_wdata_i,          // Data request Write data
    input  logic [N_MASTER-1:0][BE_WIDTH-1:0]       data_be_i,             // Data request Byte enable
    output logic [N_MASTER-1:0]                     data_gnt_o,            // Grant Incoming Request
    output logic [N_MASTER-1:0]                     data_r_valid_o,        // Data Response Valid (For LOAD/STORE commands)
    output logic [N_MASTER-1:0][DATA_WIDTH-1:0]     data_r_rdata_o,        // Data Response DATA (For LOAD commands)
    // slave side
    output  logic [N_SLAVE-1:0]                     data_req_o,            // Data request
    output  logic [N_SLAVE-1:0][ADDR_MEM_WIDTH-1:0] data_add_o,            // Data request Address
    output  logic [N_SLAVE-1:0]                     data_wen_o,            // Data request type : 0--> Store, 1 --> Load
    output  logic [N_SLAVE-1:0][DATA_WIDTH-1:0]     data_wdata_o,          // Data request Wrire data
    output  logic [N_SLAVE-1:0][BE_WIDTH-1:0]       data_be_o,             // Data request Byte enable 
    input   logic [N_SLAVE-1:0]                     data_gnt_i,            // Grant In
    input   logic [N_SLAVE-1:0][DATA_WIDTH-1:0]     data_r_rdata_i,        // Data Response DATA (For LOAD commands)
    input   logic [N_SLAVE-1:0]                     data_r_valid_i         // Valid Response 
);

  localparam ADDR_OFFSET = $clog2(DATA_WIDTH-1)-3;





endmodule
