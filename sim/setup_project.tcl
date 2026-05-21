# =============================================================================
# Vera -- Vivado 2018.2 project setup + simulation runner
# Plain ASCII, no BOM.
#
# Source from Vivado Tcl console:
#   source {C:/Users/Anubhav Gupta/Desktop/Projects/vera/sim/setup_project.tcl}
# =============================================================================

set ROOT {C:/Users/Anubhav Gupta/Desktop/Projects/vera}

# Configure xsim to run until $finish (not a fixed time window).
# This prevents the watchdog initial block from firing after the main
# $finish: launch_simulation runs "run all" internally and stops at the
# first $finish.  Without this the proc's extra "run all" would resume
# the simulator past that $finish and hit the watchdog.
set_property -name {xsim.simulate.runtime} -value {all} \
    -objects [get_filesets sim_1]

# -----------------------------------------------------------------------------
# RTL sources -> sources_1
# KEY: [list $p] forces Tcl list-quoting so Vivado's C++ Tcl_SplitList
# receives one token even when the path contains spaces.
# -----------------------------------------------------------------------------
foreach f {rtl/block_allocator.v rtl/block_table.v rtl/rw_engine.v rtl/axi4_lite_if.v rtl/prefetch_ctrl.v rtl/eviction_engine.v rtl/kv_cache_ctrl.v} {
    set p "$ROOT/$f"
    if {[llength [get_files -quiet [list $p]]] == 0} {
        add_files -norecurse [list $p]
        puts "Added RTL: $f"
    } else {
        puts "Already in project: $f"
    }
}

# -----------------------------------------------------------------------------
# Testbenches -> sim_1
# -----------------------------------------------------------------------------
foreach f {tb/tb_block_allocator.v tb/tb_block_table.v tb/tb_rw_engine.v tb/tb_axi4_lite_if.v tb/tb_prefetch_eviction.v tb/tb_kv_cache_ctrl.v} {
    set p "$ROOT/$f"
    set already [get_files -quiet -of_objects [get_filesets sim_1] [list $p]]
    if {[llength $already] == 0} {
        add_files -fileset sim_1 -norecurse [list $p]
        puts "Added TB: $f"
    } else {
        puts "Already in sim_1: $f"
    }
}

# -----------------------------------------------------------------------------
# Constraints -> constrs_1
# -----------------------------------------------------------------------------
set xdc "$ROOT/constraints/timing.xdc"
if {[llength [get_files -quiet [list $xdc]]] == 0} {
    add_files -fileset constrs_1 -norecurse [list $xdc]
    puts "Added constraints: timing.xdc"
} else {
    puts "Already in project: timing.xdc"
}

# Some Vera files use SystemVerilog syntax while retaining .v names.
foreach f {rtl/rw_engine.v tb/tb_rw_engine.v rtl/axi4_lite_if.v tb/tb_axi4_lite_if.v rtl/prefetch_ctrl.v rtl/eviction_engine.v tb/tb_prefetch_eviction.v rtl/kv_cache_ctrl.v tb/tb_kv_cache_ctrl.v} {
    set p "$ROOT/$f"
    set_property file_type SystemVerilog [get_files [list $p]]
}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "\n--- Registered sources ---"
foreach f [get_files -of_objects [get_filesets sources_1]] {
    puts "  src: [file tail $f]"
}
foreach f [get_files -of_objects [get_filesets sim_1]] {
    puts "  sim: [file tail $f]"
}

# -----------------------------------------------------------------------------
# run_sim proc
# launch_simulation runs "run all" internally (because xsim.simulate.runtime
# is set to "all" above).  No separate "run all" needed; calling it again
# would resume the simulator past the $finish and hit the watchdog.
# -----------------------------------------------------------------------------
proc run_sim {top} {
    close_sim -quiet
    reset_simulation -simset sim_1 -mode behavioral -quiet
    set_property top $top [get_filesets sim_1]
    puts "Launching: $top"
    launch_simulation
    puts "\n=== Simulation done: $top ==="
}

puts {
Setup complete.
  run_sim tb_block_allocator
  run_sim tb_block_table
  run_sim tb_rw_engine
  run_sim tb_axi4_lite_if
  run_sim tb_prefetch_eviction
  run_sim tb_kv_cache_ctrl
}
