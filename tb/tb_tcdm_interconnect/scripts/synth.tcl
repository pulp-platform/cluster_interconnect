# Copyright (c) 2018 ETH Zurich.
# Fabian Schuiki    <fschuiki@iis.ee.ethz.ch>
# Michael Schaffner <schaffner@iis.ee.ethz.ch>

#####################
##   SETUP         ##
#####################

echo "----------------------------------"
echo "--- Synthesis Script Arguments ---"
echo "----------------------------------"
echo "SRC:         $SRC                 "
echo "TOP_ENTITY:  $TOP_ENTITY          "
echo "NAME:        $NAME                "
echo "INCDIR:      $INCDIR              "
echo "OUTDIR:      $OUTDIR              "
echo "DEFINE:      $DEFINE              "
echo "LIB:         $LIB                 "
echo "----------------------------------"

set CPUS 1

set VARIANT "hp"

if {![info exists TCK]} {set TCK 1000}
if {![info exists VARIANT]} {set VARIANT hp}
if {![info exists CORNER_TRIM]} {set CORNER_TRIM 0}

if {[info exists CPUS]} {
    set_host_options -max_cores $CPUS
}

#####################
##   LOAD DESIGN   ##
#####################

# Set libraries.
if {$VARIANT == "hp"} {
    set TEMP 125C
    if {$CORNER_TRIM} {
        set VBN 0P80
        set VBP M0P80
    } else {
        set VBN 0P00
        set VBP 0P00
    }
    dz_set_pvt [list \
        GF22FDX_SC8T_104CPP_BASE_CSC20SL_SSG_0P72V_0P00V_${VBN}V_${VBP}V_${TEMP} \
        GF22FDX_SC8T_104CPP_BASE_CSC24SL_SSG_0P72V_0P00V_${VBN}V_${VBP}V_${TEMP} \
        GF22FDX_SC8T_104CPP_BASE_CSC28SL_SSG_0P72V_0P00V_${VBN}V_${VBP}V_${TEMP} \
        GF22FDX_SC8T_104CPP_BASE_CSC20L_SSG_0P72V_0P00V_${VBN}V_${VBP}V_${TEMP} \
        GF22FDX_SC8T_104CPP_BASE_CSC24L_SSG_0P72V_0P00V_${VBN}V_${VBP}V_${TEMP} \
        GF22FDX_SC8T_104CPP_BASE_CSC28L_SSG_0P72V_0P00V_${VBN}V_${VBP}V_${TEMP} \
        IN22FDX_R1PH_NFHN_W00256B016M02C256_104cpp_SSG_0P720V_${VBN}0V_${VBP}0V_${TEMP} \
        IN22FDX_R1PH_NFHN_W00256B046M02C256_104cpp_SSG_0P720V_${VBN}0V_${VBP}0V_${TEMP} \
        IN22FDX_R1PH_NFHN_W00256B128M02C256_104cpp_SSG_0P720V_${VBN}0V_${VBP}0V_${TEMP} \
    ]
    set driving_cell SC8T_BUFX4_CSC28SL
    set driving_cell_clk SC8T_CKBUFX4_CSC20SL
    set load_cell SC8T_BUFX4_CSC28SL
    set load_lib GF22FDX_SC8T_104CPP_BASE_CSC28SL_SSG_0P72V_0P00V_${VBN}V_${VBP}V_${TEMP}
}
if {$VARIANT == "lp"} {
    dz_set_pvt [list \
        GF22FDX_SC7P5TLV_116CPP_BASE_CSC28SL_SSG_0P45V_0P00V_0P85V_M1P15V_M40C \
        GF22FDX_SC7P5TLV_116CPP_BASE_CSC32SL_SSG_0P45V_0P00V_0P85V_M1P15V_M40C \
        GF22FDX_SC7P5TLV_116CPP_BASE_CSC36SL_SSG_0P45V_0P00V_0P85V_M1P15V_M40C \
        GF22FDX_SC7P5TLV_116CPP_BASE_CSC28L_SSG_0P45V_0P00V_0P85V_M1P15V_M40C \
        GF22FDX_SC7P5TLV_116CPP_BASE_CSC32L_SSG_0P45V_0P00V_0P85V_M1P15V_M40C \
        GF22FDX_SC7P5TLV_116CPP_BASE_CSC36L_SSG_0P45V_0P00V_0P85V_M1P15V_M40C \
        IN22FDX_R1PL_NFLG_W00256B016M02C256_116cpp_SSG_0P450V_0P590V_0P850V_M1P150V_M40C \
        IN22FDX_R1PL_NFLG_W00256B046M02C256_116cpp_SSG_0P450V_0P590V_0P850V_M1P150V_M40C \
        IN22FDX_R1PL_NFLG_W00256B128M02C256_116cpp_SSG_0P450V_0P590V_0P850V_M1P150V_M40C \
    ]
    set driving_cell SC7P5TLV_BUFX4_CSC36SL
    set driving_cell_clk SC7P5TLV_CKBUFX4_CSC28SL
    set load_cell SC7P5TLV_BUFX4_CSC36SL
    set load_lib GF22FDX_SC7P5TLV_116CPP_BASE_CSC36SL_SSG_0P45V_0P00V_0P85V_M1P15V_M40C
}

###########################
##   Forbid some cells   ##
###########################

# # Forbid some of the standard cells.
# if {$VARIANT == "hp"} {
#     set_dont_use [get_lib_cells */*_CSC20SL]
#     set_dont_use [get_lib_cells */*_CSC24SL]
# }
# if {$VARIANT == "lp"} {
#     # set_dont_use [get_lib_cells */*_CSC28SL]
#     # set_dont_use [get_lib_cells */*_CSC32SL]
# }

# # Generally forbid area-optimized and low drive strength cells.
# set_dont_use [get_lib_cells */*_A_*]
# set_dont_use [get_lib_cells */*X0P5_*]

######################
##   CLOCK GATING   ##
######################

set_clock_gating_style -num_stages 1 -positive_edge_logic integrated -control_point before -control_signal scan_enable

###########################
##   ELABORATE DESIGN    ##
###########################

# make library
sh mkdir -p $LIB
define_design_lib WORK -path $LIB

# delete previous designs.
remove_design -designs
sh rm -rf $LIB/*

set CLK_PIN clk_i
set RST_PIN rst_ni

analyze -format sv $SRC -define $DEFINE

elaborate  ${TOP_ENTITY}

###########################
##   APPLY CONSTRAINTS   ##
###########################

set IN_DEL  0.0
set OUT_DEL 0.0
set DELAY   $TCK

# set_critical_range 25 [current_design]
# set_leakage_optimization true

create_clock ${CLK_PIN} -period ${TCK}

set_ideal_network ${CLK_PIN}
set_ideal_network ${RST_PIN}

set_max_delay ${DELAY} -from [all_inputs] -to [all_outputs]
set_input_delay ${IN_DEL} [remove_from_collection [all_inputs] {${CLK_PIN}}] -clock ${CLK_PIN}
set_output_delay ${OUT_DEL}  [all_outputs] -clock ${CLK_PIN}

set_driving_cell  -no_design_rule -lib_cell ${driving_cell} -pin Z [all_inputs]
set_load [load_of ${load_lib}/${load_cell}/A] [all_outputs]

#######################
##   COMPILE ULTRA   ##
#######################

compile_ultra -gate_clock -scan

#################
##   NETLIST   ##
#################

change_names -rules verilog -hierarchy
define_name_rules fixbackslashes -allowed "A-Za-z0-9_" -first_restricted "\\" -remove_chars
change_names -rule fixbackslashes -h
write_file -format ddc -hierarchy -output $OUTDIR/design.ddc
write_file -format verilog -hierarchy -output $OUTDIR/design.v

#################
##   REPORTS   ##
#################

report_power  -hierarchy > $OUTDIR/power.rpt
report_timing            > $OUTDIR/timing.rpt
report_area   -hierarchy > $OUTDIR/area.rpt

exit