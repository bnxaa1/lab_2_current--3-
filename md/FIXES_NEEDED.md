# Fixes Needed

This file tracks confirmed bugs and incomplete wiring that must be resolved before the design is functional.

---

## ~~[HIGH] 1. Debounce counter too short — `one_pulse_generator.sv`~~ **FIXED**

**Was:** `counter` is a 4-bit IP firing at 15 cycles = 300 ns at 50 MHz. Too short for physical button debounce.

**Fix applied:** `clock1.sv` divides the 50 MHz system clock to `clk1ms` (1 kHz). `lab_2.sv` feeds `clk1ms` into `lock_validation`, which passes it to `one_pulse_generator`. The existing 4-bit counter now counts 15 cycles × 1 ms = **15 ms** — within the 10–20 ms target.

---

## [HIGH] 2. `supervisor_requests.sv` not instantiated — `lab_2.sv`

**Problem:** The module exists and compiles but is wired to nothing. `lab_2.sv` never instantiates it and `access_permission` has no `cmd_request` input port.

**Fix:** Add a `cmd_request` output port to `access_permission`, instantiate `supervisor_requests` in `lab_2.sv`, and connect `access_state_p` → `access_state` and the resulting `cmd_request` → `access_permission`.

---

## [HIGH] 3. S3 / S4 are dead-end states — `access_permission.sv`

**Problem:** Once the FSM enters a supervisor session (S3 or S4) there are no transitions out except `rstN` or `srst_access`. A supervisor can never exit a session normally.

**Fix:** Add a `cmd_request` input to `access_permission`. In S3 and S4, transition back to S0 when `cmd_request == EXIT_REQUEST`, and handle `UNLOCK_REQUEST` in S4 by clearing the locked condition before returning to S0.

---

## [HIGH] 4. `srst1` hardwired to 0 — `lab_2.sv` line 17

**Problem:** `ThreeBitsCounter` (failure counter) in `access_permission_wrapper` never resets. Once `locked = 1` (4 failures) the system can only recover via `resetN`. The supervisor path cannot clear the lockout.

**Fix:** Drive `srst1` from a real source — most likely an `UNLOCK_REQUEST` signal produced by `supervisor_requests` when the supervisor is in S4. Replace `assign srst1 = 1'b0` once that path is wired up (depends on fixes 2 and 3).

---

## [MEDIUM] 5. Write path permanently disabled — `lab_2.sv` lines 12–15

**Problem:** `wren = 1'b0` and `dataIn = 4'b0` are hardcoded. Password changing is completely unimplemented despite the design comment in `codeStorage.sv` describing the intended behaviour.

**Fix:** Define a password-change flow. Drive `wren`, `dataIn`, and `wStartingAddress` from a dedicated state machine or supervisor command handler. The `codeStorage` comment block describes the requirements (double-entry verification, 4–10 digit range, `1010` end marker).

---

## ~~[MEDIUM] 6. Timeout counter too narrow for 5 s — `access_permission_wrapper.sv` line 42~~ **FIXED**

**Was:** 20-bit counter, 1,000,000 compare → ~20 ms at 50 MHz.

**Fix applied:**
A new 13-bit IP `thirteenBitsCtr` (`lpm_width = 13`) replaces `TwentyBitsCounter`. Since `access_permission_wrapper` runs on `clk1ms` (1 kHz), 5,000 cycles × 1 ms = **5 s**. 13 bits is the minimum width needed (2^13 = 8,192 > 5,000).

---

## [LOW] 7. Magic number `switches == 4'd11` — `lab_2.sv` line 16

**Problem:** The value `11` that triggers the access-permission path is undocumented. Its meaning is not obvious to a reader.

**Fix:** Replace the literal with a named parameter:
```sv
localparam logic [3:0] ACCESS_TRIGGER = 4'd11;
assign enter_access = enter_d && (switches == ACCESS_TRIGGER);
```

---

## ~~[LOW] 8. `done = 1` persists into S2 — `lock_validation.sv`~~ **CONFIRMED INTENTIONAL**

**Was:** When the 9th digit is wrong, the FSM enters S2. `done` becomes 1 at the next posedge (ctr 8→9). The 10th `enter_d` in S2 immediately goes to S3.

**Analysis (confirmed 2026-04-23):** This is correct behaviour. S2 means a wrong digit was already entered — S3 (error) is the only valid outcome. Waiting for `done` or `switches==1010` before asserting the error is the right design: it lets the user finish typing before the FSM signals failure, preventing spurious early-error signals. No fix needed.

**Also confirmed correct:** The 10-digit all-correct path (done=1, eq=1 on the 10th press) correctly transitions S0 → S1. The `if(done)` branch takes priority over `end_code` and `switches==1010` in S0.
