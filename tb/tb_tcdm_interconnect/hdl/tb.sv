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
// Date: 15.08.2018
// Description: testbench for piton_icache. includes the following tests:
//
// 0) random accesses with disabled cache
// 1) random accesses with enabled cache to cacheable and noncacheable memory
// 2) linear, wrapping sweep with enabled cache
// 3) 1) with random stalls on the memory side and TLB side
// 4) nr 3) with random invalidations
//
// note that we use a simplified address translation scheme to emulate the TLB.
// (random offsets).

`include "tb.svh"

import tb_pkg::*;

module tb;

  // leave this
  timeunit 1ps;
  timeprecision 1ps;

  // tcdm configuration
  localparam string MutImpl = "newBfly"; // {"oldLic", "newLic", "newBfly"}
  localparam NumBanks       = 32;
  localparam NumMaster      = 16;
  localparam DataWidth      = 32;
  localparam MemAddrBits    = 12;
  localparam TestCycles     = 10000;

  localparam AddrWordOff    = $clog2(DataWidth-1)-3;

///////////////////////////////////////////////////////////////////////////////
// MUT signal declarations
///////////////////////////////////////////////////////////////////////////////

  logic [NumMaster-1:0] req_i;
  logic [NumMaster-1:0][DataWidth-1:0] add_i;
  logic [NumMaster-1:0] wen_i;
  logic [NumMaster-1:0][DataWidth-1:0] wdata_i;
  logic [NumMaster-1:0][DataWidth/8-1:0] be_i;
  logic [NumMaster-1:0] gnt_o;
  logic [NumMaster-1:0] rvld_o;
  logic [NumMaster-1:0][DataWidth-1:0] rdata_o;

  logic [NumBanks-1:0] cs_o;
  logic [NumBanks-1:0][MemAddrBits-1:0] add_o;
  logic [NumBanks-1:0] wen_o;
  logic [NumBanks-1:0][DataWidth-1:0] wdata_o;
  logic [NumBanks-1:0][DataWidth/8-1:0] be_o;
  logic [NumBanks-1:0][DataWidth-1:0] rdata_i;

///////////////////////////////////////////////////////////////////////////////
// TB signal declarations
///////////////////////////////////////////////////////////////////////////////

  logic clk_i, rst_ni;
  logic end_of_sim;
  logic [NumMaster-1:0] pending_req_d, pending_req_q;
  logic [NumMaster-1:0] reset_gnt_cnt_local;
  // int   gnt_cnt_local_d[0:NumMaster-1], gnt_cnt_local_q[0:NumMaster-1];
  int   gnt_cnt_d[0:NumMaster-1], gnt_cnt_q[0:NumMaster-1];
  int   req_cnt_d[0:NumMaster-1], req_cnt_q[0:NumMaster-1];
  int   wait_cnt_d[0:NumMaster-1], wait_cnt_q[0:NumMaster-1];
  int   num_cycles;
  real  req_prob;

///////////////////////////////////////////////////////////////////////////////
// helper tasks
///////////////////////////////////////////////////////////////////////////////

  // random uniform address sequence with request probability p
  task automatic randomUniformTest(input int NumCycles, input real p);
    automatic int unsigned val;
    automatic logic [$clog2(NumBanks)+AddrWordOff+MemAddrBits-1:0] addr;
    // reset the interconnect state, set number of vectors
    `APPL_WAIT_CYC(clk_i,100)
    num_cycles  = NumCycles;
    req_prob    = p;
    rst_ni      = 1'b0;
    wen_i       = '0;
    wdata_i     = '0;
    be_i        = '0;
    req_i       = '0;
    add_i       = '0;
    `APPL_WAIT_CYC(clk_i,1)
    rst_ni      = 1'b1;
    `APPL_WAIT_CYC(clk_i,100)

    // only do reads for the moment
    repeat(NumCycles) begin
      `APPL_WAIT_CYC(clk_i,1)
      for (int m=0; m<NumMaster; m++) begin
        if (~pending_req_q[m]) begin
          // decide whether to request
          void'(randomize(val) with {val>=0; val<1000;});
          if (val <= int'(p*1000.0)) begin
            // draw random word address
            void'(randomize(addr));
            add_i[m] = addr;
            req_i[m] = 1'b1;
          end else begin
            req_i[m] = 1'b0;
          end
        end
      end
    end
    `APPL_WAIT_CYC(clk_i,1)
    req_i = '0;
    add_i = '0;
  endtask : randomUniformTest

  // linear read requests with probability p
  task automatic linearTest(input int NumCycles, input real p);
    automatic int unsigned val;
    automatic logic [$clog2(NumBanks)+AddrWordOff+MemAddrBits-1:0] addr;
    // reset the interconnect state, set number of vectors
    `APPL_WAIT_CYC(clk_i,100)
    num_cycles  = NumCycles;
    req_prob    = p;
    rst_ni      = 1'b0;
    wen_i       = '0;
    wdata_i     = '0;
    be_i        = '0;
    req_i       = '0;
    add_i       = '0;
    `APPL_WAIT_CYC(clk_i,1)
    rst_ni      = 1'b1;
    `APPL_WAIT_CYC(clk_i,100)

    // only do reads for the moment
    repeat(NumCycles) begin
      `APPL_WAIT_CYC(clk_i,1)
      for (int m=0; m<NumMaster; m++) begin
        if (~pending_req_q[m]) begin
          // decide whether to request
          void'(randomize(val) with {val>=0; val<1000;});
          if (val <= int'(p*1000.0)) begin
            // increment address
            add_i[m] = add_i[m] + 4;
            req_i[m] = 1'b1;
          end else begin
            req_i[m] = 1'b0;
          end
        end
      end
    end
    `APPL_WAIT_CYC(clk_i,1)
    req_i = '0;
    add_i = '0;
  endtask : linearTest


  function automatic void printStats();
    $display("---------------------------------------");
    $display("Stats over %d cycles (p=%.2f):", num_cycles, req_prob);
    for (int m=0; m<NumMaster; m++) begin
      $display("Port %03d, num reqs: %05d, granted: %05d (estimated grant p= %.2f, avg wait cycles c= %.2f)",
        m, req_cnt_q[m], gnt_cnt_q[m], real'(gnt_cnt_q[m])/real'(req_cnt_q[m]), real'(wait_cnt_q[m])/real'(gnt_cnt_q[m]));
    end
    $display("---------------------------------------");
  endfunction : printStats


///////////////////////////////////////////////////////////////////////////////
// Clock Process
///////////////////////////////////////////////////////////////////////////////

  always @*
    begin
      do begin
        clk_i = 1;#(CLK_HI);
        clk_i = 0;#(CLK_LO);
      end while (end_of_sim == 1'b0);
      repeat (100) begin
        // generate a few extra cycle to allow
        // response acquisition to complete
        clk_i = 1;#(CLK_HI);
        clk_i = 0;#(CLK_LO);
      end
    end

///////////////////////////////////////////////////////////////////////////////
// memory emulation
///////////////////////////////////////////////////////////////////////////////

  logic [NumBanks-1:0][2**MemAddrBits-1:0][DataWidth-1:0] mem_array;
  logic [NumBanks-1:0][DataWidth-1:0] rdata_q;

  always_ff @(posedge clk_i) begin : p_mem
    if(~rst_ni) begin
      // fill memory with some random numbers
      void'(randomize(mem_array));
      rdata_q <= 'x;
    end else begin
      for(int b=0; b<NumBanks; b++) begin
        if (cs_o[b]) begin
          if (wen_o[b]) begin
            for (int j=0; j< DataWidth/8; j++) begin
              if (be_o[b][j]) mem_array[b][add_o[b]][j*8 +: 8] <= wdata_o[b][j*8 +: 8];
            end
          end else begin
            // $display("%d> %08X, %08X",b,add_o[b],mem_array[b][add_o[b]]);
            rdata_q[b] <= mem_array[b][add_o[b]];
          end
        end else begin
          rdata_q[b] <= 'x;
        end
      end
    end
  end

  assign rdata_i = rdata_q;

  // pending request tracking
  // granted reqs are cleared, ungranted reqs
  // are marked as pending
  assign pending_req_d = (pending_req_q | req_i) & ~gnt_o;

  for (genvar m=0; m<NumMaster; m++) begin
    // assign gnt_cnt_local_q[m]  = (gnt_o[m])       ? ((reset_gnt_cnt_local) ? 1 : gnt_cnt_local_d[m]  + 1) :
    //                                                 ((reset_gnt_cnt_local) ? 0 : gnt_cnt_local_q[m]);
    assign gnt_cnt_d[m]  = (gnt_o[m])             ? gnt_cnt_q[m]  + 1 : gnt_cnt_q[m];
    assign req_cnt_d[m]  = (req_i[m])             ? req_cnt_q[m]  + 1 : req_cnt_q[m];
    assign wait_cnt_d[m] = (req_i[m] & ~gnt_o[m]) ? wait_cnt_q[m] + 1 : wait_cnt_q[m];
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : p_req_pending
    if(~rst_ni) begin
      pending_req_q   <= '0;
      gnt_cnt_q       <= '{default:0};
      req_cnt_q       <= '{default:0};
      wait_cnt_q      <= '{default:0};
      // gnt_cnt_local_q <= '{default:0};
    end else begin
      pending_req_q   <= pending_req_d;
      gnt_cnt_q       <= gnt_cnt_d;
      req_cnt_q       <= req_cnt_d;
      wait_cnt_q      <= wait_cnt_d;
      // gnt_cnt_local_q <= gnt_cnt_local_d;
    end
  end

  // check the memory responses using assertions
  logic [NumMaster-1:0][$clog2(NumBanks)-1:0] bank_sel;
  logic [NumMaster-1:0][MemAddrBits-1:0] bank_addr;

  for (genvar m=0; m<NumMaster; m++) begin

    // simplifies the assertion below
    assign bank_sel[m]  = add_i[m][$clog2(NumBanks)+AddrWordOff-1:AddrWordOff];
    assign bank_addr[m] = add_i[m][$clog2(NumBanks)+AddrWordOff+MemAddrBits-1:$clog2(NumBanks)+AddrWordOff];

    bank_read : assert property(
        @(posedge clk_i) disable iff (~rst_ni) req_i[m] |-> gnt_o[m] |=> rvld_o[m] && ($past(mem_array[bank_sel[m]][bank_addr[m]],1) == rdata_o[m]))
          else $fatal (1, "rdata mismatch on master %0d: exp %08X != act %06X.", m, $past(mem_array[bank_sel[m]][bank_addr[m]],1), rdata_o[m]);
  end


///////////////////////////////////////////////////////////////////////////////
// MUT
///////////////////////////////////////////////////////////////////////////////

if (MutImpl== "oldLic") begin
  tcdm_xbar_wrap #(
    .NumMaster     ( NumMaster   ),
    .NumSlave      ( NumBanks    ),
    .AddrWidth     ( DataWidth   ),
    .DataWidth     ( DataWidth   ),
    .AddrMemWidth  ( MemAddrBits )
  ) i_tcdm_xbar_wrap (
    .clk_i   ( clk_i   ),
    .rst_ni  ( rst_ni  ),
    .req_i   ( req_i   ),
    .add_i   ( add_i   ),
    .wen_i   ( wen_i   ),
    .wdata_i ( wdata_i ),
    .be_i    ( be_i    ),
    .gnt_o   ( gnt_o   ),
    .rvld_o  ( rvld_o  ),
    .rdata_o ( rdata_o ),
    .cs_o    ( cs_o    ),
    .add_o   ( add_o   ),
    .wen_o   ( wen_o   ),
    .wdata_o ( wdata_o ),
    .be_o    ( be_o    ),
    .rdata_i ( rdata_i )
  );
end else if (MutImpl == "newLic") begin
  tcdm_interconnect #(
    .NumMaster     ( NumMaster   ),
    .NumSlave      ( NumBanks    ),
    .AddrWidth     ( DataWidth   ),
    .DataWidth     ( DataWidth   ),
    .AddrMemWidth  ( MemAddrBits ),
    .Topology      ( 0           )
  ) i_tcdm_interconnect (
    .clk_i   ( clk_i   ),
    .rst_ni  ( rst_ni  ),
    .req_i   ( req_i   ),
    .add_i   ( add_i   ),
    .wen_i   ( wen_i   ),
    .wdata_i ( wdata_i ),
    .be_i    ( be_i    ),
    .gnt_o   ( gnt_o   ),
    .rvld_o  ( rvld_o  ),
    .rdata_o ( rdata_o ),
    .cs_o    ( cs_o    ),
    .add_o   ( add_o   ),
    .wen_o   ( wen_o   ),
    .wdata_o ( wdata_o ),
    .be_o    ( be_o    ),
    .rdata_i ( rdata_i )
  );
end else if (MutImpl == "newBfly") begin
  tcdm_interconnect #(
    .NumMaster     ( NumMaster   ),
    .NumSlave      ( NumBanks    ),
    .AddrWidth     ( DataWidth   ),
    .DataWidth     ( DataWidth   ),
    .AddrMemWidth  ( MemAddrBits ),
    .Topology      ( 1           )
  ) i_tcdm_interconnect (
    .clk_i   ( clk_i   ),
    .rst_ni  ( rst_ni  ),
    .req_i   ( req_i   ),
    .add_i   ( add_i   ),
    .wen_i   ( wen_i   ),
    .wdata_i ( wdata_i ),
    .be_i    ( be_i    ),
    .gnt_o   ( gnt_o   ),
    .rvld_o  ( rvld_o  ),
    .rdata_o ( rdata_o ),
    .cs_o    ( cs_o    ),
    .add_o   ( add_o   ),
    .wen_o   ( wen_o   ),
    .wdata_o ( wdata_o ),
    .be_o    ( be_o    ),
    .rdata_i ( rdata_i )
  );
end

///////////////////////////////////////////////////////////////////////////////
// simulation coordinator process
///////////////////////////////////////////////////////////////////////////////

  initial begin : p_stim
    // seq_done
    end_of_sim       = 0;
    rst_ni           = 0;

    // print some info
    $display("TB> current configuration:");
    $display("TB> Implementation: %s",   MutImpl  );
    $display("TB> NumMaster:      %0d",  NumMaster  );
    $display("TB> NumBanks:       %0d",  NumBanks   );
    $display("TB> DataWidth:      %0d",  DataWidth  );
    $display("TB> MemAddrBits:    %0d",  MemAddrBits);
    $display("TB> TestCycles:     %0d",  TestCycles);

    // reset cycles
    `APPL_WAIT_CYC(clk_i,1)
    rst_ni        = 1'b1;
    `APPL_WAIT_CYC(clk_i,100)

    $display("TB> start with test sequences");
    // apply each test until seq_num_resp memory
    // requests have successfully completed
    ///////////////////////////////////////////////
    $display("TB> random uniform test");
    randomUniformTest(TestCycles, 0.125);
    printStats();
    randomUniformTest(TestCycles, 0.25);
    printStats();
    randomUniformTest(TestCycles, 0.5);
    printStats();
    randomUniformTest(TestCycles, 1.0);
    printStats();
    ///////////////////////////////////////////////
    $display("TB> linear test");
    linearTest(TestCycles, 1.0);
    printStats();
    ///////////////////////////////////////////////
    end_of_sim = 1;
    $display("TB> end test sequences");
  end

endmodule












