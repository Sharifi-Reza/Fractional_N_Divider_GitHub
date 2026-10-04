################################################################################    
# Fractional-N Divider - SDC (Week-4 signoff)    
# Target: TSMC 180 nm / Synopsys DC or Cadence Genus    
# RO_CLK = 131.072 kHz -> period 7629.39 ns    
################################################################################    
    
# Units depend on tool setup     values below are in nanoseconds if
# synthesis scripts set timing_unit to ns. If your flow uses ps    
# multiply periods by 1000 (see scripts/synth.tcl notes).    
    
create_clock -name clk -period 7629.39 -waveform {0 3814.695} [get_ports clk]    
    
# Async reset - do not time as data (recovery/removal optional later)    
set_false_path -from [get_ports rst_n]    
    
# N_sel arrives from SDM     sampled only at period boundary.
# Conservative external delay vs clk.    
set_input_delay  -clock clk -max 100.0 [get_ports {N_sel[*]}]    
set_input_delay  -clock clk -min   0.0 [get_ports {N_sel[*]}]    
    
# INT65K_CLK is a generated clock that drives the external T-FF.    
# Keep modest external budget     real load comes from T-FF CK pin.
set_output_delay -clock clk -max 100.0 [get_ports INT65K_CLK]    
set_output_delay -clock clk -min   0.0 [get_ports INT65K_CLK]    
    
# Optional: declare generated clock for STA of T-FF path if integrated    
# create_generated_clock -name INT65K -source [get_ports clk] \    
#   -divide_by 2 [get_ports INT65K_CLK]    
    
# Clock transition / capacitance defaults - leave to liberty unless needed    
# set_clock_transition 0.1 [get_clocks clk]    
# set_load 0.05 [get_ports INT65K_CLK]    
    
# IMPORTANT: latch-based clock mux is intentional.    
# Do not set_disable_timing on latch_out* paths without review.    
