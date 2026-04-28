# Next Steps

## Pending

### Blocked — awaiting design decisions
- **Supervisor timeout alarm**
  - Trigger: `key=1`, FSM in S2, timer expires
  - Duration: TBD (10 s / 15 s / 30 s) — determines counter IP width
  - Alarm output: dedicated LED vs shared `Err_LED` — TBD
  - Clear condition: key removal (recommended) vs successful auth vs `resetN` only — TBD
  - Implementation: separate counter in `access_permission_wrapper.sv`; resets on S0→S2 trau gnsition

### Ready
- **HEX digit echo during entry** — show each of the 5 entered digits on HEX[5:1] in real time as the user types, so the operator can verify what was entered; requires a 5-entry shift register fed by `switches` on each `enter_d` pulse, bubbled up through `lock_validation_wrapper` → `access_permission_wrapper` → `lab_2` → `DE1_SoC_golden_top`

- **Extend LEDR[0]/LEDR[1] visibility** — `error`/`correct` are 1-cycle pulses at 1 kHz (1 ms) — invisible to human eye; either remove them from LEDR and keep only in HEX0 debug, or extend through a short hold counter

- **Input range validation** — unassigned keys `A, B, C, E, F` currently treated as mismatches; 4 accidental presses lock the system
  - Fix: gate `enter_d` behind `valid_input = (switches <= 4'd9) || (switches == 4'b1101)` in `lock_validation_wrapper.sv` and `change_password.sv` ENTRY state
  - Invalid presses silently ignored — no mismatch, no counter advance, no RAM write

- **`tb_access_permission_wrapper.sv` port updates** — ✓ done: all new ports connected (`unlock_req`, `cp_complete`, `is_supervisor`, `cp_active`, `cp_ctrRst`, `cp_srst_lv`, `target_addr`, `session_active`, `enter_d`, `done`, `active_addr`); `apply_reset` initializes all new inputs to 0; supervisor addr header comment fixed (20-24 → 32-36); Tests 9b/11 terminator fixed (`4'b1010` → `4'b1101`) and state check fixed (`3'd4` → `3'd3`)
  - Test cases for password-change paths and supervisor session not yet present

## Done (this session)

- **Integrated single-scan keypad module in a new file** — added `keypad_interface_single_scan.sv` using the simpler one-column-at-a-time scan architecture with synchronized row inputs and parameterized debounce; `DE1_SoC_golden_top.v` now uses it in the keypad-only test path while the older bidirectional `keypad_interface.sv` remains in the repo for reference

- **Keypad-only HEX4 hold-on-release behavior** — in the temporary keypad-only top-level mode, `HEX4` now latches the decoded key on the debounced release edge of `kpad_enter` instead of following `kpad_pass` live; this keeps the display on the last completed key while no key is pressed

- **Temporary keypad-only top-level mode** — commented out the `lab_2` instance in `DE1_SoC_golden_top.v` and routed `HEX4` directly from `kpad_pass` so the current board build can isolate keypad decoding without the rest of the access-control system

- **Moved keypad ownership to `DE1_SoC_golden_top.v`** — `clock1` and `keypad_interface` now live at the board top level; `lab_2.sv` no longer scans physical GPIO pins and instead consumes decoded `switches` and `enter_al` inputs; `tb_lab_2.sv` updated to use the new `lab_2` interface

- **Dedicated keypad-to-HEX4 debug path** — added `keypad_pass_dbg` output in `lab_2.sv` and wired `DE1_SoC_golden_top.v` `HEX4` directly to that signal so the board-level `HEX4` display now follows the raw keypad pass value explicitly, independent of other debug naming

- **`lab_2.qsf` — full-design project cleanup** — removed stale direct pin assignments to internal `lab_2` signals (`clk`, `switches`, `enter_al`, `srst`, `correct`, `error`, `resetN`) so Pin Planner now reflects the integrated `DE1_SoC_golden_top` hardware ports only; added missing `lock_validation_wrapper.sv` and `leds.sv` to the active Quartus source list; removed standalone `DE1_SoC_keypad_test.v` from the full-design project source list to avoid project/source ambiguity

- **`counter.v` `clk_en` → `cnt_en` fix** — same master-gate bug as `ThreeBitsCounter`: `sclr` was blocked whenever `clk_en=enter_d=0`, keeping `ctr` at X and making RAM output float (XXXX); fixed by hardwiring `lpm.clk_en=1'b1` and routing external port as `lpm.cnt_en`; `codeStorage.sv` updated to `.cnt_en(clk_en)`; `one_pulse_generator.sv` updated to `.cnt_en(1'b1)`


- **`tb_lab_2.sv` — fully corrected** — `Lock_LED` port added to DUT; check added in T4 (`Lock_LED` level); `clear_ev` + `Corr_LED` check added in T5 (unlock); `Err_LED` slow-blink check added in T6 (timeout); `Corr_LED` check added in T10 (supervisor auth); all `10`/terminator comments updated to `D (4'hD=13)`; stale `resetN resets user_active` comment corrected
- **`sim_lab2.do` — wave signals updated** — `Lock_LED` added to Outputs section; new `LEDs FSM` divider added with `led1/state_reg`, `locked`, `timeOut`, `ap_corr_pulse`, `ap_err_pulse`, `sup_corr_pulse`
- **All MD files updated** — `CHANGE_PASSWORD_DESIGN.md` (FSM corrected to 5 actual states, reset semantics, port list); `DESIGN_SPECS.md` (LED section expanded, memory map rewritten with 4-region layout); `SV_FILES_OVERVIEW.md` (full rewrite: all modules described, stale Code Review Notes removed); `SESSION_SUMMARY.md` (terminator D, supervisor addr 32-36, pending tasks resolved); `MODELSIM_GUIDE*.md` (terminator D, supervisor addr 32-36, ram_sim.v, twelveBitsCounter, Lock_LED waves, state_p=3); `CHANGE_PASSWORD_PLAN.md` (marked superseded)

- **`ThreeBitsCounter` `clk_en` → `cnt_en` fix** — port renamed; `clk_en=1'b1` internally; `sclr` now always reachable regardless of `increment`; wrapper instantiation updated to `.cnt_en(increment)`
- **Terminator changed `4'hA` → `4'hD`** — updated in `lock_validation.sv`, `change_password.sv`, `ram_sim.v`, `ramm.mif`, all three testbenches
- **`leds.sv` — `twelveBitsCounter` IP** — inline 12-bit counter replaced with LPM instance
- **`leds.sv` — expanded feedback** — `timeout_in`/`locked_in` inputs; `Lock_LED` output; `TIMEOUT_ON`/`TIMEOUT_OFF` states (slow blink); `Lock_LED = locked_in` combinational
- **`lab_2.sv` — `Corr_LED` expanded** — fires on user correct auth, supervisor correct auth (`sup_corr_pulse`), `cp_complete`, and `unlock_req`
- **`lab_2.sv` — `Lock_LED` port added** — routed through `leds` instance
- **`DE1_SoC_golden_top.v` — lab_2 instantiation** — CLOCK_50, KEY[0..2] (with inversions for active-high ports), GPIO_0[35:28] for keypad, LEDR[0..4] for all LED outputs; cpu_sdram removed; all unused outputs tied off
- **`FIXES_NEEDED.md`** — all 8 original items marked resolved; T5 and T6 added and resolved/open
- **`md/PROBLEMS_SOLVED.md`** — created; 19 problems documented
- **`documentation/USER_FLOW.md`** — comprehensive rewrite with keypad layout, all LED behaviors, all signal descriptions, pending sections
