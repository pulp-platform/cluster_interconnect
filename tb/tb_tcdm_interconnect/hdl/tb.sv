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
// Description: testbench for tcdm_interconnect with random and linear access patterns.
//

`include "tb.svh"

import tb_pkg::*;

module tb;

  // leave this
  timeunit 1ps;
  timeprecision 1ps;

`ifdef BATCH_SIM
  // tcdm configuration
  localparam MutImpl        = `MUT_IMPL;
  localparam NumBanks       = `NUM_MASTER * `BANK_FACT;
  localparam NumMaster      = `NUM_MASTER;
  localparam DataWidth      = `DATA_WIDTH;
  localparam MemAddrBits    = `MEM_ADDR_BITS;
  localparam TestCycles     = `TEST_CYCLES;
`else
  localparam MutImpl        = 1; // {"oldLic", "newLic", "newBfly", "newClos"}
  localparam NumBanks       = 16;
  localparam NumMaster      = 8;
  localparam DataWidth      = 32;
  localparam MemAddrBits    = 12;
  localparam TestCycles     = 10000;
`endif

	localparam StatsFile      = "statistics.log";

  localparam AddrWordOff    = $clog2(DataWidth-1)-3;

  localparam int unsigned ClosN = 2**$clog2(int'($ceil($sqrt(real'(NumBanks) / 2.0))));
  localparam int unsigned ClosM = 2*ClosN;
  localparam int unsigned ClosR = 2**$clog2(NumBanks / ClosN);

  localparam string impl[] = {"oldLic", "newLic", "newBfly", "newClos"};

///////////////////////////////////////////////////////////////////////////////
// MUT signal declarations
///////////////////////////////////////////////////////////////////////////////

  logic [NumMaster-1:0] req_i;
  logic [NumMaster-1:0][DataWidth-1:0] add_i;
  logic [NumMaster-1:0] wen_i;
  logic [NumMaster-1:0][DataWidth-1:0] wdata_i;
  logic [NumMaster-1:0][DataWidth/8-1:0] be_i;
  logic [NumMaster-1:0] gnt_o;
  logic [NumMaster-1:0] vld_o;
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

  logic        clk_i, rst_ni;
  logic        end_of_sim;
  logic        [NumMaster-1:0] pending_req_d, pending_req_q;
  logic        [NumMaster-1:0] cnt_set;
  int unsigned cnt_val[0:NumMaster-1];
  int unsigned cnt_d[0:NumMaster-1], cnt_q[0:NumMaster-1];
  int unsigned gnt_cnt_d[0:NumMaster-1], gnt_cnt_q[0:NumMaster-1];
  int unsigned req_cnt_d[0:NumMaster-1], req_cnt_q[0:NumMaster-1];
  int unsigned bank_req_cnt_d[0:NumBanks-1], bank_req_cnt_q[0:NumBanks-1];
  int unsigned wait_cnt_d[0:NumMaster-1], wait_cnt_q[0:NumMaster-1];
  int unsigned num_cycles;
  string       name_t;
  real         pReq_t;
  int unsigned maxLen_t;
  
///////////////////////////////////////////////////////////////////////////////
// helper tasks
///////////////////////////////////////////////////////////////////////////////

  // random uniform address sequence with request probability p
  task automatic randomUniformTest(input int NumCycles, input real p);
    automatic int unsigned val;
    automatic logic [$clog2(NumBanks)+AddrWordOff+MemAddrBits-1:0] addr;
    name_t   = "random uniform";
    pReq_t   = p;
    maxLen_t = 0;
    // reset the interconnect state, set number of vectors
    `APPL_WAIT_CYC(clk_i,100)
    num_cycles  = NumCycles;
    rst_ni      = 1'b0;
    wen_i       = '0;
    wdata_i     = '0;
    be_i        = '0;
    req_i       = '0;
    add_i       = '0;
    cnt_set     = '0;
    cnt_val     = '{default:0};
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
    name_t   = "linear sweep";
    pReq_t   = p;
    maxLen_t = 0;
    // reset the interconnect state, set number of vectors
    `APPL_WAIT_CYC(clk_i,100)
    num_cycles  = NumCycles;
    rst_ni      = 1'b0;
    wen_i       = '0;
    wdata_i     = '0;
    be_i        = '0;
    req_i       = '0;
    add_i       = '0;
    cnt_set     = '0;
    cnt_val     = '{default:0};
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

  // linear read requests with random offsets and lengths with probability p
  task automatic linearRandTest(input int NumCycles, input real p, input int maxLen);
    automatic int unsigned val;
    automatic logic [$clog2(NumBanks)+AddrWordOff+MemAddrBits-1:0] addr;
    name_t   = "random linear bursts";
    pReq_t   = p;
    maxLen_t = maxLen;
    // reset the interconnect state, set number of vectors
    `APPL_WAIT_CYC(clk_i,100)
    num_cycles  = NumCycles;
    rst_ni      = 1'b0;
    wen_i       = '0;
    wdata_i     = '0;
    be_i        = '0;
    req_i       = '0;
    add_i       = '0;
    cnt_set     = '0;
    cnt_val     = '{default:0};
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
          	if (cnt_q[m]==0) begin
	          	// draw random word address
	            void'(randomize(addr));
	            add_i[m]    = addr;
	          	cnt_set[m]  = 1'b1;
          		void'(randomize(val) with {val>=1; val<maxLen;});
          		cnt_val[m]  = val;
          	end else begin
          		add_i[m]    = add_i[m]+4;
							req_i[m]    = 1'b1;
							cnt_set[m]  = 1'b0;
						end
          end else begin
          	req_i[m]    = 1'b0;
          	cnt_set[m]  = 1'b0;
          end
        end
      end
    end
    `APPL_WAIT_CYC(clk_i,1)
    req_i = '0;
    add_i = '0;
  endtask : linearRandTest

  // constant address requests with probability p
  task automatic constantTest(input int NumCycles, input real p);
    automatic int unsigned val;
    automatic logic [$clog2(NumBanks)+AddrWordOff+MemAddrBits-1:0] addr;
    name_t   = "all-to-one bank access";
    pReq_t   = p;
    maxLen_t = 0;
    // reset the interconnect state, set number of vectors
    `APPL_WAIT_CYC(clk_i,100)
    num_cycles  = NumCycles;
    rst_ni      = 1'b0;
    wen_i       = '0;
    wdata_i     = '0;
    be_i        = '0;
    req_i       = '0;
    add_i       = '0;
    cnt_set     = '0;
    cnt_val     = '{default:0};
    `APPL_WAIT_CYC(clk_i,1)
    rst_ni      = 1'b1;
    `APPL_WAIT_CYC(clk_i,100)
    addr        = 0;
    // only do reads for the moment
    repeat(NumCycles) begin
      `APPL_WAIT_CYC(clk_i,1)
      for (int m=0; m<NumMaster; m++) begin
        if (~pending_req_q[m]) begin
          // decide whether to request
          void'(randomize(val) with {val>=0; val<1000;});
          if (val <= int'(p*1000.0)) begin
            // increment address
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
  endtask : constantTest

  // random uniform address sequence with request probability p
  task automatic randPermTest(input int NumCycles, input real p);
    automatic int unsigned val;
    automatic int unsigned addr [0:NumBanks-1];
    name_t   = "random permutation test";
    pReq_t   = p;
    maxLen_t = 0;
    // fill with unique bank IDs
    for (int m=0; m<NumBanks; m++) begin
    	addr[m] = m<<AddrWordOff;
    end	
		// reset the interconnect state, set number of vectors
    `APPL_WAIT_CYC(clk_i,100)
    num_cycles  = NumCycles;
    rst_ni      = 1'b0;
    wen_i       = '0;
    wdata_i     = '0;
    be_i        = '0;
    req_i       = '0;
    add_i       = '0;
    cnt_set     = '0;
    cnt_val     = '{default:0};
    `APPL_WAIT_CYC(clk_i,1)
    rst_ni      = 1'b1;
    `APPL_WAIT_CYC(clk_i,100)

    // only do reads for the moment
    repeat(NumCycles) begin
      `APPL_WAIT_CYC(clk_i,1)
      // draw other permutation
      addr.shuffle();
      for (int m=0; m<NumMaster; m++) begin
        // decide whether to request
        void'(randomize(val) with {val>=0; val<1000;});
        if (val <= int'(p*1000.0)) begin
          // assign permuted bank addresses
          add_i[m] = addr[m%NumBanks];
          req_i[m] = 1'b1;
        end else begin
          req_i[m] = 1'b0;
        end
      end
    end
    `APPL_WAIT_CYC(clk_i,1)
    req_i = '0;
    add_i = '0;
  endtask : randPermTest

  function automatic void printStats(string file);
    // append
    int fp = $fopen(file,"a");
    // print test configuration
    $fdisplay(fp, "test config:\nnet: %s\nnumMaster: %05d\nnumBanks: %05d\ndataWidth: %05d\nmemAddrBits: %05d\ntestCycles: %05d\ntestName: %s\npReq: %e\nmaxLen: %05d", impl[MutImpl], NumMaster, NumBanks, DataWidth, MemAddrBits, TestCycles, name_t, pReq_t, maxLen_t); 
    $display(name_t);
    if (maxLen_t>0) $display("p=%.2f, maxLen=%02d", pReq_t, maxLen_t);
    else            $display("p=%.2f", pReq_t);
    $display("sim cycles: %03d", num_cycles);
    $display("---------------------------------------");
		for (int m=0; m<NumMaster; m++) begin
      $fdisplay(fp, "Port %03d: Req=%05d Gnt=%05d p=%e Wait=%e", 
      	m, req_cnt_q[m], gnt_cnt_q[m], real'(gnt_cnt_q[m])/real'(req_cnt_q[m]+0.00001), real'(wait_cnt_q[m])/real'(gnt_cnt_q[m]));
      $display("Port %03d: Req=%05d Gnt=%05d p=%.2f Wait=%.2f", 
        m, req_cnt_q[m], gnt_cnt_q[m], real'(gnt_cnt_q[m])/real'(req_cnt_q[m]+0.00001), real'(wait_cnt_q[m])/real'(gnt_cnt_q[m]));
    end
    $display("");
    for (int s=0; s<NumBanks; s++) begin
      $fdisplay(fp,"Bank %03d: Req=%05d Load=%e", 
      	s, bank_req_cnt_q[s], real'(bank_req_cnt_q[s])/real'(num_cycles));
      $display("Bank %03d: Req=%05d Load=%.2f", 
        s, bank_req_cnt_q[s], real'(bank_req_cnt_q[s])/real'(num_cycles));
    end
    $display("---------------------------------------");
    $fdisplay(fp,"");
    $fclose(fp);
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
    assign cnt_d[m]      = (cnt_set[m])             ? cnt_val[m]-1 :
                           (gnt_o[m] && cnt_q[m]>0) ? cnt_q[m]-1   :
                                                      cnt_q[m];

    assign gnt_cnt_d[m]  = (gnt_o[m])              ? gnt_cnt_q[m]  + 1 : gnt_cnt_q[m];
    assign req_cnt_d[m]  = (req_i[m])              ? req_cnt_q[m]  + 1 : req_cnt_q[m];
    assign wait_cnt_d[m] = (req_i[m] & ~gnt_o[m])  ? wait_cnt_q[m] + 1 : wait_cnt_q[m];
  end

  // assumes that banks always grant requests
  for (genvar s=0; s<NumBanks; s++) begin
    assign bank_req_cnt_d[s]  = (cs_o[s])          ? bank_req_cnt_q[s]  + 1 : bank_req_cnt_q[s];
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : p_req_pending
    if(~rst_ni) begin
      pending_req_q   <= '0;
      gnt_cnt_q       <= '{default:0};
      req_cnt_q       <= '{default:0};
      bank_req_cnt_q  <= '{default:0};
      wait_cnt_q      <= '{default:0};
      cnt_q           <= '{default:0};
    end else begin
      pending_req_q   <= pending_req_d;
      gnt_cnt_q       <= gnt_cnt_d;
      req_cnt_q       <= req_cnt_d;
      bank_req_cnt_q  <= bank_req_cnt_d;
      wait_cnt_q      <= wait_cnt_d;
      cnt_q           <= cnt_d;
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
        @(posedge clk_i) disable iff (~rst_ni) req_i[m] |-> gnt_o[m] |=> vld_o[m] && ($past(mem_array[bank_sel[m]][bank_addr[m]],1) == rdata_o[m]))
          else $fatal (1, "rdata mismatch on master %0d: exp %08X != act %06X.", m, $past(mem_array[bank_sel[m]][bank_addr[m]],1), rdata_o[m]);
  end


///////////////////////////////////////////////////////////////////////////////
// MUT
///////////////////////////////////////////////////////////////////////////////

if (MutImpl==0)  begin : g_oldLic
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
    .vld_o   ( vld_o   ),
    .rdata_o ( rdata_o ),
    .cs_o    ( cs_o    ),
    .add_o   ( add_o   ),
    .wen_o   ( wen_o   ),
    .wdata_o ( wdata_o ),
    .be_o    ( be_o    ),
    .rdata_i ( rdata_i )
  );
end else if (MutImpl == 1) begin : g_newLic
  tcdm_interconnect #(
    .NumIn         ( NumMaster   ),
    .NumOut        ( NumBanks    ),
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
    .vld_o   ( vld_o   ),
    .rdata_o ( rdata_o ),
    .cs_o    ( cs_o    ),
    .add_o   ( add_o   ),
    .wen_o   ( wen_o   ),
    .wdata_o ( wdata_o ),
    .be_o    ( be_o    ),
    .rdata_i ( rdata_i )
  );
end else if (MutImpl == 2) begin : g_newBfly
  tcdm_interconnect #(
    .NumIn         ( NumMaster   ),
    .NumOut        ( NumBanks    ),
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
    .vld_o   ( vld_o  ),
    .rdata_o ( rdata_o ),
    .cs_o    ( cs_o    ),
    .add_o   ( add_o   ),
    .wen_o   ( wen_o   ),
    .wdata_o ( wdata_o ),
    .be_o    ( be_o    ),
    .rdata_i ( rdata_i )
  );
end else if (MutImpl == 3) begin : g_newClos
  tcdm_interconnect #(
    .NumIn         ( NumMaster   ),
    .NumOut        ( NumBanks    ),
    .AddrWidth     ( DataWidth   ),
    .DataWidth     ( DataWidth   ),
    .AddrMemWidth  ( MemAddrBits ),
    .Topology      ( 2           ),
    .ClosN         ( ClosN       ),
    .ClosM         ( ClosM       ),
    .ClosR         ( ClosR       )
  ) i_tcdm_interconnect (
    .clk_i   ( clk_i   ),
    .rst_ni  ( rst_ni  ),
    .req_i   ( req_i   ),
    .add_i   ( add_i   ),
    .wen_i   ( wen_i   ),
    .wdata_i ( wdata_i ),
    .be_i    ( be_i    ),
    .gnt_o   ( gnt_o   ),
    .vld_o   ( vld_o  ),
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
    $display("---------------------------------------");
    $display("TCDM Network Traffic Simulation");
    $display("---------------------------------------");
    $display("Current configuration:");
    $display("Network:        %s",   impl[MutImpl]);
    $display("NumMaster:      %0d",  NumMaster    );
    $display("NumBanks:       %0d",  NumBanks     );
    $display("DataWidth:      %0d",  DataWidth    );
    $display("MemAddrBits:    %0d",  MemAddrBits  );
    $display("TestCycles:     %0d",  TestCycles   );
    $display("StatsFile:      %s",   StatsFile    );

    // reset cycles
    `APPL_WAIT_CYC(clk_i,1)
    rst_ni        = 1'b1;
    `APPL_WAIT_CYC(clk_i,100)

    $display("start with test sequences");
    $display("---------------------------------------");
    ///////////////////////////////////////////////
    // apply each test until seq_num_resp memory
    // requests have successfully completed
    ///////////////////////////////////////////////
    // uniform traffic
    randomUniformTest(TestCycles, 0.125);
    printStats(StatsFile);
    randomUniformTest(TestCycles, 0.25);
    printStats(StatsFile);
    randomUniformTest(TestCycles, 0.5);
    printStats(StatsFile);
    randomUniformTest(TestCycles, 1.0);
    printStats(StatsFile);
    ///////////////////////////////////////////////
    // random permutations (no banking conflicts)
    randPermTest(TestCycles, 0.125);
    printStats(StatsFile);
    randPermTest(TestCycles, 0.25);
    printStats(StatsFile);
    randPermTest(TestCycles, 0.5);
    printStats(StatsFile);
    randPermTest(TestCycles, 1.0);
    printStats(StatsFile);
    ///////////////////////////////////////////////
		linearRandTest(TestCycles, 0.125, 100);
    printStats(StatsFile);
    linearRandTest(TestCycles, 0.25, 100);
    printStats(StatsFile);
    linearRandTest(TestCycles, 0.5, 100);
    printStats(StatsFile);
    linearRandTest(TestCycles, 1.0, 100);
    printStats(StatsFile);
    ///////////////////////////////////////////////
  	// some special cases
    linearTest(TestCycles, 1.0);
    printStats(StatsFile);
    constantTest(TestCycles, 1.0);
    printStats(StatsFile);
    ///////////////////////////////////////////////
    end_of_sim = 1;
    $display("end test sequences");
    $display("---------------------------------------");
  end

endmodule












