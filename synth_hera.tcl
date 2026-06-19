# Hera KV Cache Controller -- out-of-context synthesis
# Target: Artix-7 xc7a100tcsg324-1 @ 100 MHz

set RTL_DIR [file normalize [file join [file dirname [info script]] rtl]]

create_project -in_memory -part xc7a100tcsg324-1

read_verilog -sv [glob $RTL_DIR/*.v]

synth_design \
    -top kv_cache_ctrl \
    -part xc7a100tcsg324-1 \
    -mode out_of_context \
    -flatten_hierarchy rebuilt

# Create clock constraint AFTER synthesis (after design is open)
create_clock -period 10.000 -name clk [get_ports clk]

report_utilization  -file synth_utilization.rpt
report_timing_summary -file synth_timing.rpt -max_paths 10

puts "===== Utilization ====="
set util [report_utilization -return_string]
foreach line [split $util \n] {
    if {[regexp {Slice LUT|Slice Reg|BRAM|DSP} $line]} { puts $line }
}

puts "===== Timing ====="
set ts [report_timing_summary -return_string -max_paths 1]
set found 0
foreach line [split $ts \n] {
    if {[regexp {^\s*clk\s+} $line]} { set found 1 }
    if {$found && [string length [string trim $line]] > 5} {
        puts $line
        if {$found > 3} break
        incr found
    }
}
