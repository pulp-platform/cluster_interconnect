onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group TB /tb/add_i
add wave -noupdate -expand -group TB /tb/add_o
add wave -noupdate -expand -group TB /tb/bank_addr
add wave -noupdate -expand -group TB /tb/bank_sel
add wave -noupdate -expand -group TB /tb/be_i
add wave -noupdate -expand -group TB /tb/be_o
add wave -noupdate -expand -group TB /tb/clk_i
add wave -noupdate -expand -group TB /tb/cs_o
add wave -noupdate -expand -group TB /tb/end_of_sim
add wave -noupdate -expand -group TB /tb/gnt_cnt_d
add wave -noupdate -expand -group TB /tb/gnt_cnt_q
add wave -noupdate -expand -group TB /tb/gnt_o
add wave -noupdate -expand -group TB /tb/mem_array
add wave -noupdate -expand -group TB /tb/MemAddrBits
add wave -noupdate -expand -group TB /tb/num_cycles
add wave -noupdate -expand -group TB /tb/NumBanks
add wave -noupdate -expand -group TB /tb/NumMaster
add wave -noupdate -expand -group TB /tb/DataWidth
add wave -noupdate -expand -group TB /tb/pending_req_d
add wave -noupdate -expand -group TB /tb/pending_req_q
add wave -noupdate -expand -group TB /tb/rdata_i
add wave -noupdate -expand -group TB /tb/rdata_o
add wave -noupdate -expand -group TB /tb/rdata_q
add wave -noupdate -expand -group TB /tb/req_i
add wave -noupdate -expand -group TB /tb/req_prob
add wave -noupdate -expand -group TB /tb/rst_ni
add wave -noupdate -expand -group TB /tb/rvld_o
add wave -noupdate -expand -group TB /tb/Topology
add wave -noupdate -expand -group TB /tb/wdata_i
add wave -noupdate -expand -group TB /tb/wdata_o
add wave -noupdate -expand -group TB /tb/wen_i
add wave -noupdate -expand -group TB /tb/wen_o
add wave -noupdate -divider MUT
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/clk_i
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/rst_ni
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/req_i
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/add_i
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/wen_i
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/wdata_i
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/be_i
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/rdata_i
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/NumMaster
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/NumSlave
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/AddrWidth
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/DataWidth
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/BeWidth
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/AddrMemWidth
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/Topology
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/SlaveSelWidth
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/AddrWordOff
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/gnt_o
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/rvld_o
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/rdata_o
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/cs_o
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/add_o
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/wen_o
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/wdata_o
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/be_o
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/genblk1/bank_we_be_addr
add wave -noupdate -expand -group MUT -expand /tb/i_tcdm_interconnect/genblk1/bank_sel_d
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/genblk1/bank_sel_q
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/genblk1/req_local
add wave -noupdate -expand -group MUT -expand /tb/i_tcdm_interconnect/genblk1/gnt_local
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/genblk1/gnt_local_reshape
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/genblk1/vld_d
add wave -noupdate -expand -group MUT /tb/i_tcdm_interconnect/genblk1/vld_q
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {5015447 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 193
configure wave -valuecolwidth 221
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {41407 ps}
