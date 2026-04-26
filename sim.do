# sim.do — compile and run tb_lock_validation_wrapper
#
# Run from ModelSim transcript after Phase 1 (library setup) is done:
#   cd {C:/Users/mahaz/Desktop/lab_2_current (3)}
#   do sim.do
#
# Libraries lpm_ver, altera_mf_ver, altera_ver, sgate_ver, altera_lnsim_ver
# must already exist in this directory (see md/MODELSIM_GUIDE.md Phase 1).

# ── Compile Altera IP files (Verilog) ────────────────────────────
# clock1 / sixteenbitsctr not needed: lock_validation_wrapper no longer
# instantiates clock1 — the top level (lab_2.sv) owns that instance.
vlog -work work counter.v
vlog -work work thirteenBitsCtr.v
vlog -work work ThreeBitsCounter.v
vlog -work work TwentyBitsCounter.v
vlog -work work ram.v

# ── Compile design files (SystemVerilog, dependency order) ───────
vlog -sv -work work one_pulse_generator.sv
vlog -sv -work work codeStorage.sv
vlog -sv -work work lock_validation.sv
vlog -sv -work work lock_validation_wrapper.sv

# ── Compile testbench ─────────────────────────────────────────────
vlog -sv -work work tb_lock_validation_wrapper.sv

# ── Launch simulation ─────────────────────────────────────────────
vsim -t 1ns \
     -L lpm_ver \
     -L altera_mf_ver \
     -L altera_ver \
     -L sgate_ver \
     -L altera_lnsim_ver \
     work.tb_lock_validation_wrapper

# ── Waveforms ─────────────────────────────────────────────────────
add wave -divider "TB Control"
add wave /tb_lock_validation_wrapper/clk
add wave /tb_lock_validation_wrapper/resetN
add wave /tb_lock_validation_wrapper/srst

add wave -divider "Inputs"
add wave /tb_lock_validation_wrapper/enter_al
add wave /tb_lock_validation_wrapper/switches

add wave -divider "Outputs"
add wave /tb_lock_validation_wrapper/correct
add wave /tb_lock_validation_wrapper/error

add wave -divider "Internal"
add wave /tb_lock_validation_wrapper/dut/clk1ms
add wave /tb_lock_validation_wrapper/dut/enter_d
add wave /tb_lock_validation_wrapper/dut/done
add wave /tb_lock_validation_wrapper/dut/code

# ── Run ───────────────────────────────────────────────────────────
run -all
