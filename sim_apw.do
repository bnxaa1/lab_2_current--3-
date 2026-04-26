# sim_apw.do — compile and run tb_access_permission_wrapper
#
# Run from ModelSim transcript after library setup (see md/MODELSIM_GUIDE.md Phase 1):
#   cd {C:/Users/mahaz/Desktop/lab_2_current (3)}
#   do sim_apw.do

# ── Altera IP (Verilog) ──────────────────────────────────────────────────────
vlog -work work counter.v
vlog -work work thirteenBitsCtr.v
vlog -work work ThreeBitsCounter.v
vlog -work work ram.v

# ── Design files (SystemVerilog, dependency order) ───────────────────────────
vlog -sv -work work one_pulse_generator.sv
vlog -sv -work work codeStorage.sv
vlog -sv -work work lock_validation.sv
vlog -sv -work work lock_validation_wrapper.sv
vlog -sv -work work access_permission.sv
vlog -sv -work work access_permission_wrapper.sv

# ── Testbench ─────────────────────────────────────────────────────────────────
vlog -sv -work work tb_access_permission_wrapper.sv

# ── Launch ────────────────────────────────────────────────────────────────────
vsim -t 1ns \
     -L lpm_ver \
     -L altera_mf_ver \
     -L altera_ver \
     -L sgate_ver \
     -L altera_lnsim_ver \
     work.tb_access_permission_wrapper

# ── Waveforms ─────────────────────────────────────────────────────────────────
add wave -divider "TB Control"
add wave /tb_access_permission_wrapper/clk
add wave /tb_access_permission_wrapper/resetN
add wave /tb_access_permission_wrapper/srst_access
add wave /tb_access_permission_wrapper/key_raw
add wave /tb_access_permission_wrapper/key_to_dut

add wave -divider "Inputs"
add wave /tb_access_permission_wrapper/enter_al
add wave /tb_access_permission_wrapper/switches

add wave -divider "Outputs"
add wave /tb_access_permission_wrapper/correct
add wave /tb_access_permission_wrapper/error
add wave /tb_access_permission_wrapper/Corr_LED
add wave /tb_access_permission_wrapper/Err_LED
add wave /tb_access_permission_wrapper/locked
add wave /tb_access_permission_wrapper/timeOut
add wave /tb_access_permission_wrapper/state_p

add wave -divider "Internal – access_permission"
add wave /tb_access_permission_wrapper/dut/ap1/state_reg
add wave /tb_access_permission_wrapper/dut/rst_lv
add wave /tb_access_permission_wrapper/dut/effective_rst_lv
add wave /tb_access_permission_wrapper/dut/increment
add wave /tb_access_permission_wrapper/dut/ap_rst_timeoutCtr

add wave -divider "Internal – timeout counter"
add wave /tb_access_permission_wrapper/dut/ThirteenBitsCounter
add wave /tb_access_permission_wrapper/dut/rst_timeoutCtr

add wave -divider "Internal – lock_validation_wrapper"
add wave /tb_access_permission_wrapper/dut/lvw1/u_lock_validation/state_reg
add wave /tb_access_permission_wrapper/dut/lvw1/enter_d_raw
add wave /tb_access_permission_wrapper/dut/enter_d
add wave /tb_access_permission_wrapper/dut/lvw1/done
add wave /tb_access_permission_wrapper/dut/lvw1/code
add wave /tb_access_permission_wrapper/dut/rStartingAddress

add wave -divider "Failure counter"
add wave /tb_access_permission_wrapper/dut/threeBitsCounter

# ── Run ───────────────────────────────────────────────────────────────────────
run -all
