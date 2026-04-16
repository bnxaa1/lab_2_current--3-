# Fixes Needed

This file tracks confirmed bugs and incomplete wiring that must be resolved before the design is functional.

---

## [HIGH] 1. Debounce counter too short — `one_pulse_generator.sv`

**Problem:** `counter` is a 4-bit IP. `done_clk = &ctr` fires at `ctr = 15`, which is only **300 ns** at 50 MHz. Physical buttons need ~10–20 ms of debounce time (~500K–1M cycles).

**Fix:** Replace the 4-bit `counter` instance inside `one_pulse_generator` with a wider counter (e.g. a new 20-bit IP similar to `TwentyBitsCounter`) and update `done_clk` to compare against the correct cycle count for the target debounce window.

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

## [MEDIUM] 6. Timeout counter too narrow for 5 s — `access_permission_wrapper.sv` line 42

**Problem:** `TwentyBitsCounter` is 20 bits (max 1,048,575). The current compare value of 1,000,000 gives ~20 ms at 50 MHz. A 5-second timeout requires counting to **250,000,000**, which needs a **28-bit counter** (`2^28 = 268,435,456`).

**Fix:**
1. Generate a new 28-bit counter IP in Quartus (or widen the existing one).
2. Update the declaration in `access_permission_wrapper.sv`:
   ```sv
   logic [27:0] twentyBitsCounter;
   ```
3. Update the compare:
   ```sv
   assign timeOut = (twentyBitsCounter == 28'd250_000_000);
   ```

---

## [LOW] 7. Magic number `switches == 4'd11` — `lab_2.sv` line 16

**Problem:** The value `11` that triggers the access-permission path is undocumented. Its meaning is not obvious to a reader.

**Fix:** Replace the literal with a named parameter:
```sv
localparam logic [3:0] ACCESS_TRIGGER = 4'd11;
assign enter_access = enter_d && (switches == ACCESS_TRIGGER);
```

---

## [LOW] 8. `done = 1` persists into S2 — `lock_validation.sv`

**Problem:** When the digit at position 9 is wrong the FSM enters S2, but `done` is still 1 (ctr has not changed). The very next `enter_d` in S2 immediately transitions to S3 with no chance for further entry.

**Fix:** Confirm whether this is the intended behaviour for a max-length wrong entry. If not, gate the S2 → S3 transition on `done` only after `srst` has cleared and a new attempt begins, or restructure the `done` check in S0.
