# Problems Solved

A chronological record of every confirmed bug, design flaw, and wiring gap that was identified and resolved across the development of lab_2.

---

## 1. Debounce window too short (300 ns at 50 MHz)

**Root cause:** `one_pulse_generator` used a 4-bit LPM counter counting 15 cycles at the raw 50 MHz system clock — debounce window was 300 ns, far below the 10–20 ms needed for a physical button.

**Fix:** `clock1.sv` divides 50 MHz → `clk1ms` (1 kHz). All modules that touch keypad signals now run on `clk1ms`. The 15-cycle debounce becomes 15 ms.

---

## 2. Timeout counter too narrow for 5 s

**Root cause:** A 20-bit counter comparing against 1,000,000 was used. At 50 MHz this was ~20 ms, not 5 s.

**Fix:** Replaced with `thirteenBitsCtr` (13-bit LPM). At 1 kHz (clk1ms), 5,000 cycles = 5 s. 13 bits is the minimum width needed (2^13 = 8,192 > 5,000).

---

## 3. `supervisor_requests` not instantiated

**Root cause:** Module existed but was never wired into `lab_2.sv`. `access_permission` had no `cmd_request` input.

**Fix:** Full rewrite of `supervisor_requests.sv`. Replaced the `access_state[2:0]` bus interface with a `session_active` 1-bit input. Replaced single `cmd_request[2:0]` output bus with individual 1-bit signals: `exit_req`, `unlock_req`, `change_user_req`, `change_super_req`. Fully instantiated in `lab_2.sv`.

---

## 4. S3 / S4 were dead-end states

**Root cause:** Once the supervisor entered S3 (unlocked supervisor session) or S4 (locked supervisor session), there were no FSM transitions out — only a hard `resetN` could exit.

**Fix:** S3 and S4 merged into a single S3 (locked vs unlocked discriminated by `input_cond[2]` inside S3). Exit handled externally: `exit_req` from `supervisor_requests` drives `srst_access`, which resets the AP FSM, `lock_validation` FSM, `codeStorage` counter, and timeout counter in one signal.

---

## 5. Failure counter hardwired to never reset

**Root cause:** `rst_failureCtr` was `assign srst1 = 1'b0` in `lab_2.sv`. Once `locked=1` (4 failures) the system was permanently locked until `resetN`.

**Fix:** `ThreeBitsCounter.sclr` connected to `rst_failureCtr | ap_rst_failureCtr | unlock_req`. Supervisor unlock and user correct authentication both clear the failure counter.

---

## 6. Write path permanently disabled

**Root cause:** `wren=1'b0` and `dataIn=4'b0` were hardcoded in `lab_2.sv`. Password changing was completely unimplemented.

**Fix:** `change_password.sv` designed and implemented from scratch. Double-buffer address-swap architecture: new password written to inactive RAM region, verified by `lock_validation`, then `cp_complete` atomically flips `user_active`/`super_active` register in the wrapper.

---

## 7. Magic `switches == 4'd11` gate on authentication start

**Root cause:** `enter_access = enter_d && (switches == 4'd11)` — the first keypress only triggered authentication if `switches` was exactly 11. This undocumented value meant the first digit was silently ignored unless `switches=11`.

**Fix:** Gate removed. `enter_access = enter_d`. The first digit press is the authentication trigger directly — no separate start condition needed.

---

## 8. `srst` in `access_permission` S0 suppressed first digit

**Root cause:** `access_permission` asserted `srst` (codeStorage reset) continuously in S0. Altera LPM `sclr` has priority over `clk_en`, so when the user pressed the first digit, `enter_d` fired but `sclr` was also active — the counter reset instead of advancing.

**Fix:** `srst` in S0 gated: only asserted when `!enter`. On the cycle `enter_d=1`, `srst` deasserts, allowing the counter to advance.

---

## 9. `ThreeBitsCounter.sclr` silently ignored when `increment=0`

**Root cause:** `ThreeBitsCounter` was instantiated with `.clk_en(increment)`. Altera LPM `sclr` requires `clk_en=1` to execute. When `unlock_req=1` (supervisor clears lockout) but `increment=0` (no wrong attempt in progress), `clk_en=0` → `sclr` ignored → counter stayed at 4 → `locked` remained high after unlock.

The two LPM enable ports were used with their roles swapped:
- `clk_en` (master gate, blocks `sclr`) was connected to `increment`
- `cnt_en` (count-only gate, does NOT block `sclr`) was tied to `1'b1` unused

**Fix:** `ThreeBitsCounter.v` — port renamed from `clk_en` to `cnt_en`; `clk_en` tied internally to `1'b1`. Instantiation updated to `.cnt_en(increment)`. Now `sclr` fires unconditionally whenever any reset source is asserted.

---

## 10. Altsyncram defparam mismatch — RAM output floating in simulation

**Root cause:** `ram.v` defparam had `numwords_a/b=256, widthad_a/b=8` but the actual MIF had `DEPTH=64` and ports were 6-bit. Mismatch caused altsyncram to fail initialisation from the MIF — output was floating (`x`) throughout simulation.

**Fix:** Created `ram_sim.v` — a behavioral replacement with the same module name and port list. 64×4 memory array, 1-cycle registered output (matching `outdata_reg_b=CLOCK0`), hardcoded MIF content in `initial` block. `sim_lab2.do` compiles `ram_sim.v` instead of `ram.v`.

---

## 11. `press_key` task used `automatic` — force statement failed in ModelSim

**Root cause:** `task automatic press_key` — automatic tasks allocate variables on the stack. ModelSim 10.5b does not allow `force` statements to use automatic task variables.

**Fix:** Removed `automatic` keyword from `press_key`. Task becomes static — `force uut.switches = digit` works correctly.

---

## 12. `enter_d` fires at wrong digit (digit 3 instead of digit 2)

**Root cause:** `one_pulse_generator` full round-trip is ~37 `clk1ms` cycles. `press_key` had `repeat(5)` after `enter_al=1` — total hold was only 25 cycles. The next press started 12 cycles before OPG returned to S0. OPG S4 was still running when the next `enter_al` fell → OPG treated it as bounce → rejected the digit → digit registered one press late.

**Fix:** Changed `repeat(5)` to `repeat(25)` → total 45 cycles > 37 OPG cycle. Each press fully completes before the next begins.

---

## 13. `sixteenbitsctr` not found in simulation (vsim-3033)

**Root cause:** `clock1.sv` instantiates `sixteenbitsctr` IP. `sim_lab2.do` compile list was missing `sixteenbitsctr.v`.

**Fix:** Added `vlog -work work sixteenbitsctr.v` to `sim_lab2.do`.

---

## 14. `lock_validation` produced spurious error pulses while locked

**Root cause:** While `locked=1` and no supervisor key, `enter_d` still reached `lock_validation`. The FSM would compare against RAM (which held the stored password), potentially firing `error` pulses and incrementing the failure counter further — making an already-locked system rack up phantom failures.

**Fix:** `lock_validation_wrapper` holds `lock_validation` FSM in synchronous reset via `.srst(rst_lv | (locked && !key))`. While locked and no supervisor key, the FSM stays in S0 and never compares digits. Also, `enter_d` is gated: `enter_d = enter_d_raw && (!locked || key)` — blocks `codeStorage` counter advance too.

---

## 15. `ThreeBitsCounter.sclr` — `clk_en` port renamed to `cnt_en` in wrapper IP

**Root cause:** See Problem 9. `ThreeBitsCounter.v` was a wizard-generated file with `clk_en` as the top-level port. Renaming the exposed port and tying `clk_en=1'b1` internally was the cleanest fix without regenerating the IP.

**Fix:** `ThreeBitsCounter.v` modified: module port `clk_en` → `cnt_en`; internal LPM `.clk_en(1'b1)`, `.cnt_en(cnt_en)`. `access_permission_wrapper.sv` instantiation updated to `.cnt_en(increment)`.

---

## 16. Supervisor address region at addr 20 — MSB encoding inconsistent

**Root cause:** Supervisor password was at addr 20 (`5'b10100`). The address encoding was not consistent with the `{key, active_bit, 4'b0000}` scheme (which places supervisor at addr 32 when `key=1, active_bit=0`).

**Fix:** Supervisor password moved to addr 32–36. `ramm.mif` updated. Address derivation: `rStartingAddress = {key, key ? super_active : user_active, 4'b0000}` — bit 5 = key (user/super), bit 4 = region swap bit (A/B).

---

## 17. Terminator key changed from `A` (4'hA) to `D` (4'hD)

**Root cause:** `A` (top-right of keypad) was unintuitive as a terminator. Users naturally expect a confirm key at the bottom-right.

**Fix:** Terminator changed to `D` (4'hD = 4'b1101, bottom-right key). Updated in `lock_validation.sv`, `change_password.sv`, `ram_sim.v`, `ramm.mif`, and all three testbenches.

---

## 18. `leds.sv` used inline 12-bit counter register

**Root cause:** The 12-bit timing counter was implemented as an `always_ff` register inside `leds.sv`. An existing `twelveBitsCounter` LPM IP was unused.

**Fix:** Replaced inline counter with `twelveBitsCounter` instance. `sclr` driven by `ctr_rst` (already computed combinatorially). Counter removed from `always_ff` reset block — every state entry asserts `ctr_rst=1` before the counter is checked, so the loss of async reset is safe.

---

## 19. LED feedback missing for timeout, locked state, supervisor auth, and password change

**Root cause:** `Corr_LED` only fired on user correct auth. `Err_LED` only fired on wrong password. Timeout, lockout, supervisor auth success, unlock, and password change success all gave no visual feedback.

**Fix:**
- `leds.sv` — added `timeout_in`, `locked_in` inputs; added `Lock_LED` output; added `TIMEOUT_ON`/`TIMEOUT_OFF` states (512 ms slow blink on `Err_LED`); `Lock_LED = locked_in` (combinational, always reflects lock state).
- `lab_2.sv` — `Corr_LED` now fires on: user correct auth (`ap_corr_pulse`), supervisor correct auth (`sup_corr_pulse` = rising edge of `session_active`), password change success (`cp_complete`), and supervisor unlock (`unlock_req`). All four OR into `corr_in`.
- `DE1_SoC_golden_top.v` — `Lock_LED` mapped to `LEDR[4]`.
