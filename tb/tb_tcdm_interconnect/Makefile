# Copyright 2019 ETH Zurich and University of Bologna.
# Copyright and related rights are licensed under the Solderpad Hardware
# License, Version 0.51 (the "License"); you may not use this file except in
# compliance with the License.  You may obtain a copy of the License at
# http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
# or agreed to in writing, software, hardware and materials distributed under
# this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied. See the License for the
# specific language governing permissions and limitations under the License.
#
# Author: Michael Schaffner <schaffner@iis.ee.ethz.ch>, ETH Zurich
# Date: 21.03.2019
# Description: Makefile for the interconnect testbench.

batch-list     ?= batch.list
results        ?= sim-results
library        := work
toplevel       := tb
src-list       := tb.list
src            := $(shell xargs printf '\n%s' < $(src-list)  | cut -b 1-)

matlab_version ?= -2018b

questa_version ?= -10.7b
compile_flag   += +cover+i_dut -incr -64 -nologo
sim_opts       += -64 -coverage -classdebug -voptargs="+acc"
incdir         +="../common/"+"../../rtl/low_latency_interco"

# filter the batch-list first
batch-name   := $(shell cat $(batch-list) | grep -v '\#' | cut -d - -f 1)
batch-config := $(shell cat $(batch-list) | grep -v '\#' | cut -d - -f 1-)

build: clean
	vlib${questa_version} $(library)
	vlog${questa_version} -work $(library) -pedanticerrors $(src) $(compile_flag) +incdir+$(incdir)
	touch $(library)/.build

# this starts modelsim with gui
sim: build
	vsim${questa_version} -lib $(library) $(toplevel) -do "do wave.do" $(sim_opts)

# batch mode without gui
simc: build
	vsim${questa_version} -lib $(library) $(toplevel) -c -do "run -all; exit" $(sim_opts)

clean:
	rm -rf $(library)
	rm -rf $(batch-name)
	rm -rf transcript statistics.log vsim.wlf modelsim.ini

clean-all: clean
	rm -rf $(results)
	
# runs the configurations defined in the batch-list file and gathers the statistics logs
$(batch-name):
	mkdir $@
	vlib${questa_version} $@/$(library)
	vlog${questa_version} -work $@/$(library) -pedanticerrors $(src) $(compile_flag) +incdir+$(incdir) $(subst $@-, , $(filter $@-%, $(batch-config))) > $@/compile.log
	@echo $@ started
	cd $@ && vsim${questa_version} -lib $(library) $(toplevel) -c -do "run -all; exit" $(sim_opts) > /dev/null
	@echo $@ finished
	cp $@/transcript     $(results)/$@_transcript.log
	cp $@/statistics.log $(results)/$@_statistics.log


batch: clean
	mkdir -p $(results)
	$(MAKE) $(batch-name)

plot: 
	matlab$(matlab_version) -nosplash -nodesktop -r "addpath(genpath('./matlab')); run plot_sims.m"

.PHONY: clean sim simc build batch plot
