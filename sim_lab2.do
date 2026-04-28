# sim_lab2.do — compile and run tb_lab_2 (full system testbench)
#
# Run from ModelSim transcript after library setup (see md/MODELSIM_GUIDE.md Phase 1):
#   cd {C:/Users/mahaz/Desktop/lab_2_current (3)}
#   do sim_lab2.do

# ── Altera IP (Verilog) ───────────────────────────────────────────────────────
vlog -work work counter.v
vlog -work work sixteenbitsctr.v
vlog -work work thirteenBitsCtr.v
vlog -work work ThreeBitsCounter.v
vlog -work work ram_sim.v
vlog -work work twelveBitsCounter.v

# ── Design files (SystemVerilog, dependency order) ────────────────────────────
vlog -sv -work work clock1.sv
vlog -sv -work work keypad_interface.sv
vlog -sv -work work one_pulse_generator.sv
vlog -sv -work work codeStorage.sv
vlog -sv -work work lock_validation.sv
vlog -sv -work work lock_validation_wrapper.sv
vlog -sv -work work access_permission.sv
vlog -sv -work work access_permission_wrapper.sv
vlog -sv -work work supervisor_requests.sv
vlog -sv -work work change_password.sv
vlog -sv -work work leds.sv
vlog -sv -work work lab_2.sv

# ── Testbench ─────────────────────────────────────────────────────────────────
vlog -sv -work work tb_lab_2.sv

# ── Launch ────────────────────────────────────────────────────────────────────
vsim -t 1ns \
     -L lpm_ver \
     -L altera_mf_ver \
     -L altera_ver \
     -L sgate_ver \
     -L altera_lnsim_ver \
     work.tb_lab_2

# ── Waveforms ─────────────────────────────────────────────────────────────────
add wave -divider "TB Control"
add wave /tb_lab_2/clk
add wave /tb_lab_2/resetN
add wave /tb_lab_2/srst_access
add wave /tb_lab_2/key

add wave -divider "Keypad (forced)"
add wave /tb_lab_2/uut/switches
add wave /tb_lab_2/uut/enter_al

add wave -divider "Outputs"
add wave /tb_lab_2/correct
add wave /tb_lab_2/error
add wave /tb_lab_2/Corr_LED
add wave /tb_lab_2/Err_LED
add wave /tb_lab_2/Lock_LED

add wave -divider "LEDs FSM"
add wave /tb_lab_2/uut/led1/state_reg
add wave /tb_lab_2/uut/locked
add wave /tb_lab_2/uut/timeOut
add wave /tb_lab_2/uut/ap_corr_pulse
add wave /tb_lab_2/uut/ap_err_pulse
add wave /tb_lab_2/uut/sup_corr_pulse

add wave -divider "AP FSM"
add wave /tb_lab_2/uut/access_state_p
add wave /tb_lab_2/uut/apw1/ap1/state_reg
add wave /tb_lab_2/uut/session_active
add wave /tb_lab_2/uut/locked

add wave -divider "lock_validation"
add wave /tb_lab_2/uut/apw1/lvw1/u_lock_validation/state_reg
add wave /tb_lab_2/uut/enter_d
add wave /tb_lab_2/uut/done
add wave /tb_lab_2/uut/apw1/lvw1/code
add wave /tb_lab_2/uut/apw1/rStartingAddress

add wave -divider "Failure / Timeout counters"
add wave /tb_lab_2/uut/apw1/threeBitsCounter
add wave /tb_lab_2/uut/apw1/ThirteenBitsCounter
add wave /tb_lab_2/uut/timeOut

add wave -divider "supervisor_requests"
add wave /tb_lab_2/uut/sr1/state_reg
add wave /tb_lab_2/uut/exit_req
add wave /tb_lab_2/uut/unlock_req
add wave /tb_lab_2/uut/change_user_req
add wave /tb_lab_2/uut/change_super_req

add wave -divider "change_password"
add wave /tb_lab_2/uut/cp1/state_reg
add wave /tb_lab_2/uut/cp_active
add wave /tb_lab_2/uut/cp_complete
add wave /tb_lab_2/uut/cp_fail
add wave /tb_lab_2/uut/target_addr
add wave /tb_lab_2/uut/active_addr
add wave /tb_lab_2/uut/cp_wren
add wave /tb_lab_2/uut/dataIn_cp

add wave -divider "Address swap registers"
add wave /tb_lab_2/uut/apw1/user_active
add wave /tb_lab_2/uut/apw1/super_active

# ── Run ───────────────────────────────────────────────────────────────────────
run -all
