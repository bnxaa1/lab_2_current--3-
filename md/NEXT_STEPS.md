# Next Steps

## Testing
- `tb_lock_validation_wrapper.sv` — ModelSim testbench for `lock_validation_wrapper`; 5 test scenarios
- `sim.do` — ready-to-run ModelSim script (compile + vsim + waves + run)
- `md/MODELSIM_GUIDE.md` — full step-by-step guide including one-time library setup

## Pending

### Blocked — awaiting design decisions (see `md/DESIGN_SPECS.md` section 5)
- **Supervisor alarm duration** — 10 s / 15 s / 30 s; determines counter IP width (14-bit for 15 s, 15-bit for 30 s)
- **Alarm output type** — dedicated top-level `alarm` port vs shared `Err_LED`; affects port list and `leds.sv`
- **Alarm clear condition** — key removal (recommended) vs successful auth vs `resetN` only
- **Wrong supervisor password → immediate alarm?** — affects S5 path in `access_permission.sv`

### Ready to implement (design confirmed in `md/DESIGN_SPECS.md`)
- **`access_permission_wrapper.sv` — expose new ports and wire supervisor signals**
  - Add `input logic srst_supervisor` — driven by `exit_req` from `supervisor_requests`; OR into existing `srst_access` path or pass directly
- **`lab_2.sv` — top-level integration**
  - Instantiate `supervisor_requests`; connect `session_active`, `locked`, `enter_d`, `switches`
  - Wire `exit_req` → `srst_access` on wrapper; wire `unlock_req` → wrapper `unlock_req` input
  - Instantiate `change_password`; add 6 signal muxes + `lv_srst` (see `md/CHANGE_PASSWORD_PLAN.md`)
- **Supervisor timeout alarm — add dedicated counter to `access_permission_wrapper.sv`**
  - Separate counter from user `thirteenBitsCtr`; resets on S0→S2 transition
  - Counter width and compare value depend on duration decision (see `md/DESIGN_SPECS.md` section 3)
  - Alarm output latches; clear condition and output type pending decisions

### Pending — after `change_password.sv` is implemented
- **`lab_2.sv` — wire `cp_done` to `supervisor_requests`**
  - `assign cp_done = cp_complete | cp_fail;` from `change_password` outputs
  - Cancel path: supervisor presses 1010 as first digit during ENTRY → `change_password` ERROR → `cp_fail` → `cp_done=1` → `supervisor_requests` → `NO_REQUEST` → supervisor can EXIT or choose again

## Done
- **`access_permission.sv` — S3/S4 merge + `session_active` output:** S4 removed as reachable state; S3 now handles both locked and not-locked supervisor sessions via `input_cond[2]`; `session_active` output added; exit and unlock handled externally via `srst_access` and `unlock_req`; port list regrouped
- **`supervisor_requests.sv` — full rewrite:** replaced `access_state[2:0]`/`cmd_request_in[2:0]` with `session_active`, `locked`, `enter_d`, `cp_done`, `switches`; output changed from `cmd_request[2:0]` bus to individual 1-bit signals `exit_req`, `unlock_req`, `change_user_req`, `change_super_req`; `UNLOCK_REQUEST` auto-clears to `NO_REQUEST` after 1 cycle (pulse); `CHANGE_USER/SUPER` wait for `cp_done` then return to `NO_REQUEST`; cancel path via early 1010 press → `cp_fail` → `cp_done`
- **`access_permission_wrapper.sv` — `srst_access` added to timeout counter reset:** `rst_timeoutCtr = timeOut | ap_rst_timeoutCtr | srst_access`; session exit now also resets the 13-bit timeout counter
- `tb_access_permission_wrapper.sv` — `always @(posedge locked)` now immediately forces `key=1`, so the supervisor key is held high from the clock edge where lockout asserts
- `tb_access_permission_wrapper.sv` — after `locked=1`, the testbench now immediately drives `key=1` and keeps it high for locked supervisor authentication instead of running a locked user-input check first
- `tb_access_permission_wrapper.sv` — added `enter_supervisor_digit` task that forces `key=1` throughout every supervisor password press/release cycle; locked supervisor checks now use it
- `tb_access_permission_wrapper.sv` — supervisor authentication case moved to locked-system flow; `key` is held high during the full supervisor password entry so S2 does not abort
- `tb_access_permission_wrapper.sv` — Test 9c updated to use supervisor authentication while locked (`key=1`, `2,0,2,6,1010`) instead of clearing lockout with `rst_failureCtr`
- `.clinerules` — created Cline project rules mirroring `CLAUDE.md` and summarizing Markdown project guidance/context
- **lock_validation FSM locked gate:** `lock_validation_wrapper` now holds lock_validation FSM in reset via `.srst(rst_lv | (locked && !key))` — prevents `error`/`correct` from firing while system is locked and no supervisor key present (enter_al gating rejected because it risks spurious one_pulse_generator pulses on key insert)
- **Supervisor RAM region moved to addr 20:** `ramm.mif` updated; supervisor password is `2,0,2,6,1010` (5 presses, end-marker terminated); `rStartingAddress` in wrapper changed to `5'b10100` (20) for `key=1`
- **TB event flags:** Added `ev_correct`, `ev_error`, `ev_Corr_LED`, `ev_Err_LED` latching flags + `clear_ev` task; all test checks use captured edges instead of live levels — fixes false FAIL on 1-cycle pulses
- **TB failure counter accumulation fixed:** Tests 2, 3, 4, 5 now use `apply_reset` (not `sync_reset`) after each error-generating test; prevents ThreeBitsCounter accumulation across tests
- **TB tests 11/12 supervisor password fixed:** Now enters `2, 0, 2, 6, 1010` to match updated RAM; guide RAM table and troubleshooting entry updated to match
- **`srst_access` full reset:** `effective_rst_lv = rst_lv | srst_access` in wrapper ensures `srst_access` resets AP FSM, lock_validation FSM, and codeStorage counter together
- **tb_access_permission_wrapper.sv updated:** apply_reset now pulses `rst_failureCtr` to clear ThreeBitsCounter; Tests 9b/9c added (enter_d gate verification + unlock check); Tests 11/12 added (supervisor correct auth, not-locked→S3 and locked→S4); Test 10 comment updated; sim_apw.do updated with new internal signals
- **Timeout counter reset:** `rst_timeoutCtr` added as dedicated output of `access_permission`; fires only on S0→S1 (user auth start); wrapper gates it with `timeOut` via `rst_timeoutCtr = timeOut | ap_rst_timeoutCtr`
- **enter_d gate when locked:** `lock_validation_wrapper` now gates `enter_d_raw` → `enter_d` with `(!locked || key)`; blocks codeStorage counter and lock_validation FSM advances while system is locked and no supervisor key present
- **rst_lv in S5:** `access_permission` now asserts `rst_lv=1` in the error state so codeStorage counter and lock_validation FSM reset cleanly on every error→S0 path
- **access_permission.sv S0 srst fix:** `srst` now only fires when `!enter` so the counter can advance on the first digit press (LPM sclr has priority over clk_en — without this fix, press 1 didn't advance the counter)
- **access_permission_wrapper enter_access fix:** removed `switches==11` gate; `enter_access = enter_d` (first press IS the auth trigger, no separate start signal)
- **tb_access_permission_wrapper.sv + sim_apw.do:** 10 test cases (correct user, wrong digits, early end marker, key interrupt, key removal, srst_access mid-entry, timeout, 4 failures → locked)
- `lock_validation_wrapper.sv` — simplified for user-password-only validation with minimized top-level pins
- `leds.sv` — 4-bit `counter` IP instantiated for slow clock: 14-cycle period at `clk1ms` → `clk_slow` with exact 50% duty cycle; uses `>` comparisons (`q > 12` for reset, `q > 6` for output); double-comma port syntax error fixed
- `lock_validation.sv` — full edge case analysis done; 10-digit correct entry confirmed working; fix #8 (`done=1` in S2) confirmed intentional (see FIXES_NEEDED)
- **`change_password.sv` — rewritten:** COPY states removed; address-swap approach; `inactive_addr = active_addr ^ 6'b010000`; 6-bit addresses; FSM: IDLE→ENTRY_RST→ENTRY→VERIFY_RST→VERIFY_WAIT→VERIFY→DONE/ERROR
- **`leds.sv` — rewritten:** 4-bit counter removed; 12-bit ms counter; FSM: IDLE→CORR_HOLD (3 000 ms) for `Corr_LED`; IDLE→BLINK_ON→BLINK_OFF×3 (250 ms each) for `Err_LED`; both latch 1-cycle input pulse
- **`access_permission_wrapper.sv` — swap registers added:** `user_active`/`super_active` flip-flops; `rStartingAddress` now `{key, key ? super_active : user_active, 4'b0000}`; `cp_complete`+`is_supervisor` inputs added; `session_active`+`unlock_req` ports added; `ThreeBitsCounter.sclr` ORs `unlock_req`
- `access_permission_wrapper.sv` — switched from `TwentyBitsCounter` to `thirteenBitsCtr` (13-bit, minimum needed for 5 000 cycles); `thirteenBitsCtr.qip` added to `lab_2.qsf`
- Fix #1 (debounce): `clock1.sv` added — divides 50 MHz → `clk1ms` (1 kHz); fed into `lock_validation` → `one_pulse_generator` gets 15 ms debounce via existing 4-bit counter
- Fix #6 (timeout): new `thirteenBitsCtr` IP (13-bit); compare `13'd5_000` = 5 s at `clk1ms`
- `lab_2.qsf` — `change_password.sv` and `thirteenBitsCtr.qip` added
- `md/SV_FILES_OVERVIEW.md` — code review notes added, `clock1.sv` section added
- `md/FIXES_NEEDED.md` — created with 8 issues; fixes #1, #6, #8 resolved
- `md/CHANGE_PASSWORD_PLAN.md` — full design plan
