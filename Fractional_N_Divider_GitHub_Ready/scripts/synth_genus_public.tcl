################################################################################
# Cadence Genus synthesis for the Fractional-N Divider.
# Public/portable version: no institutional or PDK path is hard-coded.
#
# Required environment variable:
#   TSMC180_LIB_DIR=/path/to/authorized/library/directory
#
# Run:
#   genus -f scripts/synth_genus_public.tcl | tee sim/gate/genus_console.log
################################################################################

if {![info exists ::env(TSMC180_LIB_DIR)]} {
    puts stderr "ERROR: set TSMC180_LIB_DIR to your authorized technology-library directory"
    exit 2
}

set SCRIPT_DIR [file dirname [file normalize [info script]]]
set ROOT_DIR   [file normalize [file join $SCRIPT_DIR ..]]
cd $ROOT_DIR

set TOP       fractional_n_divider
set RTL_FILE  [file join $ROOT_DIR rtl ${TOP}.v]
set SDC_FILE  [file join $ROOT_DIR constraints fractional_n_divider.sdc]
set OUT_DIR   [file join $ROOT_DIR netlist]
set REP_DIR   [file join $ROOT_DIR sim gate]

file mkdir $OUT_DIR
file mkdir $REP_DIR

set_db init_lib_search_path [list $::env(TSMC180_LIB_DIR)]
set_db library {typical.lib}
set_db script_search_path [list $SCRIPT_DIR]
set_db auto_ungroup none
set_db write_vlog_top_module_first true
set_db remove_assigns true
set_db information_level 1

read_hdl -language sv $RTL_FILE
elaborate
set_top_module $TOP
check_design -unresolved > [file join $REP_DIR ${TOP}_check_design.rpt]

source $SDC_FILE
init_design
report_clocks > [file join $REP_DIR ${TOP}_clocks.rpt]

syn_generic
syn_map
syn_opt

report_area                 > [file join $REP_DIR ${TOP}_area.rpt]
report_gates                > [file join $REP_DIR ${TOP}_gates.rpt]
report_timing -max_paths 10 > [file join $REP_DIR ${TOP}_timing.rpt]
report_power                > [file join $REP_DIR ${TOP}_power.rpt]
report_clocks               > [file join $REP_DIR ${TOP}_clocks_final.rpt]

write_hdl > [file join $OUT_DIR ${TOP}_postsyn.v]
write_sdf -version 3.0 -timescale ps -nonegcheck -setuphold split -recrem split \
          > [file join $OUT_DIR ${TOP}_postsyn.sdf]
write_script > [file join $OUT_DIR ${TOP}_constraints.g]

puts "GENUS_SYNTHESIS_COMPLETE"
quit
