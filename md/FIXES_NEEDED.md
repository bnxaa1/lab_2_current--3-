# Fixes Needed

This file tracks confirmed bugs and incomplete wiring that must be resolved before the design is functional.

---

## ~~[HIGH] 1. Debounce counter too short — `one_pulse_generator.sv`~~ **FIXED**

**Was:** `counter` is a 4-bit IP firing at 15 cycles = 300 ns at 50 MHz. Too short for physical button debounce.

**Fix applied:** `clock1.sv` divides the 50 MHz system clock to `clk1ms` (1 kHz). `lab_2.sv` feeds `clk1ms` into `lock_validation`, which passes it to `one_pulse_generator`. The existing 4-bit counter now counts 15 cycles × 1 ms = **15 ms** — within the 10–20 ms target.

---

## ~~[HIGH] 2. `supervisor_requests.sv` not instantiated — `lab_2.sv`~~ **FIXED**

**Was:** The module existed and compiled but was wired to nothing.

**Fix applied:** `supervisor_requests` fully instantiated in `lab_2.sv`. Replaced `access_state[2:0]` bus coupling with `session_active` 1-bit signal. Individual 1-bit outputs `exit_req`, `unlock_req`, `change_user_req`, `change_super_req` routed directly to each destination.

---

## ~~[HIGH] 3. S3 / S4 are dead-end states — `access_permission.sv`~~ **FIXED**

**Was:** Once the FSM entered a supervisor session there were no transitions out except `rstN`.

**Fix applied:** S3 and S4 merged into single S3. Exit handled externally: `exit_req` from `supervisor_requests` drives `srst_access` at wrapper level. `srst_access` resets AP FSM, `lock_validation` FSM, `codeStorage` counter, and timeout counter together.

---

## ~~[HIGH] 4. `srst1` hardwired to 0 — failure counter never reset~~ **FIXED**

**Was:** `ThreeBitsCounter` never reset. Once `locked=1` the system could only recover via `resetN`.

**Fix applied:** `sclr` of `ThreeBitsCounter` ORs `unlock_req | ap_rst_failureCtr | rst_failureCtr`. Both the supervisor unlock path and the user correct path clear the counter.

---

## ~~[MEDIUM] 5. Write path permanently disabled — `lab_2.sv`~~ **FIXED**

**Was:** `wren=1'b0` and `dataIn=4'b0` hardcoded.

**Fix applied:** `change_password.sv` fully implemented. Address-swap double-buffer design: new password written to inactive region, verified, then `cp_complete` flips `user_active`/`super_active` register atomically. `wren` and `dataIn` driven from `change_password` during ENTRY state.

---

## ~~[MEDIUM] 6. Timeout counter too narrow for 5 s — `access_permission_wrapper.sv`~~ **FIXED**

**Was:** 20-bit counter, 1,000,000 compare → ~20 ms at 50 MHz.

**Fix applied:** 13-bit `thirteenBitsCtr` IP; system runs on `clk1ms` (1 kHz); 5,000 cycles = 5 s. 13 bits minimum needed (2^13 = 8,192 > 5,000).

---

## ~~[LOW] 7. Magic number `switches == 4'd11` — `lab_2.sv`~~ **FIXED**

**Was:** Value `11` triggering the access-permission path was undocumented.

**Fix applied:** Gate removed entirely. `enter_access = enter_d` — the first digit press IS the authentication trigger. No separate start signal needed.

---

## ~~[LOW] 8. `done = 1` persists into S2 — `lock_validation.sv`~~ **CONFIRMED INTENTIONAL**

**Analysis (confirmed 2026-04-23):** S2 means a wrong digit was already entered — S3 (error) is the only valid outcome. Waiting for `done` or the terminator before asserting error is correct: it lets the user finish typing before the FSM signals failure, preventing spurious early-error signals.

---

## ~~[HIGH] T5. `ThreeBitsCounter.sclr` silently ignored when `increment=0` — `access_permission_wrapper.sv`~~ **FIXED**

**Was:** `ThreeBitsCounter` instantiated with `.clk_en(increment)`. Altera LPM `sclr` only fires when `clk_en=1`. When `unlock_req=1` but `increment=0` (no wrong attempt in progress), `sclr` was silently ignored — counter stayed at 4, `locked` stayed high after supervisor unlock.

**Fix applied:**
- `ThreeBitsCounter.v` — port renamed from `clk_en` to `cnt_en`; internally `clk_en` tied to `1'b1` so `sclr` is always reachable.
- `access_permission_wrapper.sv` — instantiation updated to `.cnt_en(increment)`.
- `cnt_en=0` blocks counting but does NOT block `sclr` — the correct role separation for the two LPM enable ports.

---

## [MEDIUM] T6. Input range validation — unassigned keypad keys not filtered

**Problem:** The keypad can produce `A, B, C, E, F` (4'hA, 4'hB, 4'hC, 4'hE, 4'hF). These are unassigned in the password scheme (only `0–9` and `D` terminator are valid). Pressing an unassigned key during password entry causes a mismatch → counts as a wrong attempt → 4 such presses lock the system. During `change_password` ENTRY, unassigned keys are written to RAM as password characters, creating passwords the user cannot reproduce reliably.

**Fix needed:** Gate `enter_d` in `lock_validation` and `change_password` behind a validity check:
```sv
valid_input = (switches <= 4'd9) || (switches == 4'b1101);
```
Only process keypresses when `valid_input=1`. Invalid keys should be silently ignored — no mismatch, no counter advance, no RAM write.

**Affects:** `lock_validation.sv` or `lock_validation_wrapper.sv` (gate `enter_d`), and `change_password.sv` ENTRY state.
