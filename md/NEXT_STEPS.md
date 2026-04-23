# Next Steps

## Testing
- `tb_lock_validation_wrapper.sv` — ModelSim testbench for `lock_validation_wrapper`; 5 test scenarios
- `sim.do` — ready-to-run ModelSim script (compile + vsim + waves + run)
- `md/MODELSIM_GUIDE.md` — full step-by-step guide including one-time library setup

## Pending
- `lab_2.sv` — instantiate `change_password` + `supervisor_requests`, add 6 signal muxes + `lv_srst`
- `access_permission.sv` — add EXIT_REQUEST transitions in S3/S4 (fix #3 from FIXES_NEEDED)
- `leds.sv` — LED output logic not yet written (corr_led_out / err_led_out driven by nothing)

## Done
- `lock_validation_wrapper.sv` — simplified for user-password-only validation with minimized top-level pins
- `leds.sv` — 4-bit `counter` IP instantiated for slow clock: 14-cycle period at `clk1ms` → `clk_slow` with exact 50% duty cycle; uses `>` comparisons (`q > 12` for reset, `q > 6` for output); double-comma port syntax error fixed
- `lock_validation.sv` — full edge case analysis done; 10-digit correct entry confirmed working; fix #8 (`done=1` in S2) confirmed intentional (see FIXES_NEEDED)
- `change_password.sv` — FSM reviewed and drawn; 12-state FSM confirmed correct (IDLE→ENTRY_RST→ENTRY→VERIFY_RST→VERIFY_WAIT→VERIFY→COPY_PREP→COPY_WAIT1→COPY_WAIT2→COPY→DONE/ERROR)
- `access_permission_wrapper.sv` — switched from `TwentyBitsCounter` to `thirteenBitsCtr` (13-bit, minimum needed for 5 000 cycles); `thirteenBitsCtr.qip` added to `lab_2.qsf`
- Fix #1 (debounce): `clock1.sv` added — divides 50 MHz → `clk1ms` (1 kHz); fed into `lock_validation` → `one_pulse_generator` gets 15 ms debounce via existing 4-bit counter
- Fix #6 (timeout): new `thirteenBitsCtr` IP (13-bit); compare `13'd5_000` = 5 s at `clk1ms`
- `lab_2.qsf` — `change_password.sv` and `thirteenBitsCtr.qip` added
- `md/SV_FILES_OVERVIEW.md` — code review notes added, `clock1.sv` section added
- `md/FIXES_NEEDED.md` — created with 8 issues; fixes #1, #6, #8 resolved
- `md/CHANGE_PASSWORD_PLAN.md` — full design plan
