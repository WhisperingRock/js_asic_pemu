# open_vivado.tcl -- build the js_asic_pemu Vivado project from the repo and open it
#
# Run from anywhere (the script finds the repo from its own location):
#
#   vivado -source 03_software/scripts/open_vivado.tcl
#   vivado -source 03_software/scripts/open_vivado.tcl -tclargs xc7a100tcsg324-1   ;# another part
#
# The project is created fresh in <repo>/vivado_project/ (gitignored) every
# time. Source files are referenced in place, not copied, so edits you make in
# VS Code show up in Vivado and edits in Vivado land in the repo.
#
# What goes where:
#   design   (sources_1) every .sv under 02_hardware except testbenches
#   sim      (sim_1)     *_tb.sv, *_tbN.sv, and anything in a tb/ or tests/ folder
#   constrs  (constrs_1) every .xdc under 02_hardware
#   memory   (sources_1) every .mem under 03_software/assembler (program.mem,
#                        receive.mem, ...). Vivado copies them next to the
#                        simulator, so $readmemh("<name>.mem", ...) finds them
#                        by file name. Keep the names unique.

# ---------------------------------------------------------------- settings
# FPGA part. Default is the Basys 3 (Artix-7 35T); pass another with -tclargs.
set part xc7a35tcpg236-1
if {$argc > 0} { set part [lindex $argv 0] }

set proj_name js_asic_pemu
set synth_top basys3_top
set sim_top   state_machine_tb

# ---------------------------------------------------------------- paths
set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize [file join $script_dir .. ..]]
set hw_dir     [file join $repo_root 02_hardware]
set proj_dir   [file join $repo_root vivado_project]
set asm_dir    [file join $repo_root 03_software assembler]

# ---------------------------------------------------------------- helpers
# Tcl's glob isn't recursive, so walk the directories ourselves.
proc find_files {dir pattern} {
    set found [glob -nocomplain -types f -directory $dir $pattern]
    foreach sub [glob -nocomplain -types d -directory $dir *] {
        set found [concat $found [find_files $sub $pattern]]
    }
    return [lsort $found]
}

proc is_testbench {path} {
    if {[regexp {/(tb|tests)/} $path]} { return 1 }
    return [regexp {_tb[0-9]*\.sv$} [file tail $path]]
}

# ---------------------------------------------------------------- collect files
set design_files {}
set sim_files    {}
foreach f [find_files $hw_dir *.sv] {
    if {[is_testbench $f]} { lappend sim_files $f } else { lappend design_files $f }
}

set xdc_files [find_files $hw_dir *.xdc]

if {[llength $design_files] == 0} {
    error "no design files found under $hw_dir"
}

# ---------------------------------------------------------------- check the part
# The Vivado installer only installs the device families you pick. If Artix-7
# wasn't picked, create_project would fail with a less obvious error.
if {[llength [get_parts -quiet $part]] == 0} {
    error "FPGA part $part is not installed in this Vivado.\
           Add it with Help > Add Design Tools or Devices... > 7 Series (Artix-7)."
}

# ---------------------------------------------------------------- build the project
puts "Creating $proj_name in $proj_dir (part $part)"
create_project $proj_name $proj_dir -part $part -force
set_property target_language Verilog [current_project]

add_files -norecurse -fileset sources_1 $design_files
if {[llength $sim_files] > 0} {
    add_files -norecurse -fileset sim_1 $sim_files
}

if {[llength $xdc_files] > 0} {
    add_files -norecurse -fileset constrs_1 $xdc_files
}

set mem_files [find_files $asm_dir *.mem]
if {[llength $mem_files] > 0} {
    add_files -norecurse -fileset sources_1 $mem_files
} else {
    puts "WARNING: no .mem files under $asm_dir -- run the assembler first"
}

set_property top $synth_top [get_filesets sources_1]
set_property top $sim_top   [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# ---------------------------------------------------------------- summary
puts ""
puts "Design files:"
foreach f $design_files { puts "  [string range $f [string length $repo_root]+1 end]" }
puts "Simulation files:"
foreach f $sim_files    { puts "  [string range $f [string length $repo_root]+1 end]" }
puts "Memory files:"
foreach f $mem_files    { puts "  [string range $f [string length $repo_root]+1 end]" }
puts "Constraints:"
foreach f $xdc_files    { puts "  [string range $f [string length $repo_root]+1 end]" }
puts "Synthesis top: $synth_top    Simulation top: $sim_top"
puts "Project: [file join $proj_dir $proj_name.xpr]"