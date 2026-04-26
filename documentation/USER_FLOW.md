# User Flow

This document describes every user interaction path through the system, the expected outcomes, and the edge cases and problems that were identified and resolved for each path.

---

## Actors

| Actor | Description |
|---|---|
| **User** | Normal person entering a password to unlock the system |
| **Supervisor** | Trusted person holding the physical key; can unlock, change passwords |

---

## 1. Normal User Authentication

### Happy path
1. System is idle in **S0**.
2. User presses first digit on keypad (`switches` + `enter_al` pulse).
   - This is the auth trigger — no separate start button.
   - `access_permission` transitions S0 → S1; timeout counter resets to 0.
3. User enters remaining digits one at a time. Each press:
   - `one_pulse_generator` debounces the press (15 ms window at 1 kHz).
   - `codeStorage` counter advances; digit at `rStartingAddress + ctr` is compared against `switches` by `lock_validation`.
4. User presses end-marker (`switches = 4'b1010`).
   - All digits matched → `correct=1` → S1 → S6 → `Corr_LED` ON (3 s static) → S0.
   - Any digit mismatched → `error=1` → S1 → S5 → `Err_LED` blinks 3× → S0; failure counter +1.

### Edge cases handled

| Problem | Resolution |
|---|---|
| First digit press must not be suppressed by `srst` | `access_permission` S0 only asserts `srst` when `!enter`; LPM `sclr` has priority over `clk_en` so the counter would freeze on press 1 without this guard |
| `correct`/`error` are 1-cycle pulses — level checks always read 0 | Testbench uses `ev_correct`/`ev_error` edge-latching flags instead of live signal levels |
| Failure counter accumulates across testbench tests | `apply_reset` pulses `rst_failureCtr` after every error-generating test to clear `ThreeBitsCounter` |

---

## 2. User Timeout

### Flow
1. User presses at least one digit (enters S1).
2. User stalls — no further input for **5 000 ms** (5 s at 1 kHz).
3. `timeOut` fires → `access_permission` S1 → S0; `codeStorage` counter and `lock_validation` FSM reset via `rst_lv`.

### Edge cases handled

| Problem | Resolution |
|---|---|
| Timeout counter must reset to 0 on every new auth attempt | `rst_timeoutCtr` fires only on S0→S1 transition (first digit press); dedicated output of `access_permission` |
| Timeout counter was 20-bit (too narrow for 5 s at 50 MHz) | Replaced with `thirteenBitsCtr` (13-bit); system runs on `clk1ms` (1 kHz) so 5 000 cycles = 5 s |
| `srst_access` (session exit) did not reset the timeout counter | Added `srst_access` to `rst_timeoutCtr` OR chain in wrapper |
| Supervisor path must have no timeout | `timeOut` only checked in S1 (user state); S2 and S3 ignore it |

---

## 3. System Lockout After 4 Failures

### Flow
1. User enters 4 wrong passwords → `ThreeBitsCounter` reaches 4 → `locked=1`.
2. While locked, all user digit presses are blocked:
   - `enter_d` gate: `enter_d = enter_d_raw && (!locked || key)` — blocks codeStorage counter and `lock_validation` FSM advances.
   - `lock_validation` held in synchronous reset: `srst = rst_lv | (locked && !key)`.
3. No LED feedback, no error signal, no counter advance while locked without supervisor key.

### Edge cases handled

| Problem | Resolution |
|---|---|
| `lock_validation` FSM could still tick on `enter_d_raw` while locked, producing spurious `error` pulses and incrementing the failure counter | Added `srst = rst_lv \| (locked && !key)` to `lock_validation`; FSM held in S0 when locked and no key — never compares digits |
| Gating `enter_al` (instead of `enter_d`) was considered but rejected | Masking `enter_al` at key insertion risks a spurious debounce pulse from `one_pulse_generator` when the gate releases |
| `rst_failureCtr` hardwired to 0 — lockout was permanent | Wired to `ap_rst_failureCtr` (user correct path) OR `unlock_req` (supervisor unlock); both clear `ThreeBitsCounter` |

---

## 4. Supervisor Key Interrupt During User Auth

### Flow
1. User is mid-entry in S1.
2. Supervisor inserts physical key (`key=1`).
3. `access_permission` S1: detects `key=1` → asserts `rst_lv=1` → resets `codeStorage` counter and `lock_validation` FSM → transitions to S0.
4. User entry is cleanly aborted; system returns to idle.

### Edge cases handled

| Problem | Resolution |
|---|---|
| Counter and FSM left in dirty state after key interrupt | `rst_lv=1` on S1 key detection resets both before S0 |

---

## 5. Supervisor Authentication

### Flow
1. Supervisor inserts physical key (`key=1`).
2. Supervisor presses first digit → `input_cond` matches `3'b011` or `3'b111` → S0 → S2.
   - `key` must remain high for entire S2 sequence; if `key` drops to 0 at any point → `rst_lv=1`, S2 → S0 (key-removal abort).
3. Supervisor enters password: `2, 0, 2, 6, 1010` (5 presses, end-marker terminated; RAM addr 20–24).
4. On `correct`:
   - → **S3** (supervisor session; handles both locked and not-locked via `locked` signal).
5. On `error` → S5 → S0 (same error path as user; no failure count for supervisor).
6. Supervisor path has **no timeout** (S2 ignores `timeOut`).

### Edge cases handled

| Problem | Resolution |
|---|---|
| Supervisor password region was at addr 10; pointed to zeros | Moved to addr 20–24 in `ramm.mif`; `rStartingAddress = key ? 5'b10100 : 5'b00000` |
| `key` dropping briefly during supervisor digit entry would abort S2 | `enter_supervisor_digit` task in testbench forces `key_raw=1` before, during, and after every press/release cycle |
| S3 and S4 were separate states requiring locked check on S2 exit | Merged into single S3; `locked` discriminates behaviour inside S3 directly via `input_cond[2]` |
| S3/S4 were dead-end states — no exit possible except `resetN` | Exit handled externally: `exit_req` from `supervisor_requests` drives `srst_access`; session clears cleanly |

---

## 6. Supervisor Session Commands

After reaching S3, the supervisor selects a command using a single digit press + enter:

| Digit | Command | Available |
|---|---|---|
| `1` | Change user password | S3 always |
| `2` | Exit session → S0 | S3 always |
| `3` | Unlock system (clear failure counter) | S3 when `locked=1` only |
| `4` | Change supervisor password | S3 always |

### Command mechanics

- `supervisor_requests.sv` reads `enter_d` + `switches` while `session_active=1`.
- Each command maps to an individual 1-bit output signal: `exit_req`, `unlock_req`, `change_user_req`, `change_super_req`.

### EXIT (`exit_req`)
- `exit_req=1` drives `srst_access=1` at wrapper level.
- Resets: AP FSM → S0, `lock_validation` FSM, `codeStorage` counter, timeout counter.
- Does NOT reset failure counter.
- `session_active` drops → `supervisor_requests` auto-clears to `NO_REQUEST`.

### UNLOCK (`unlock_req`)
- `unlock_req` is a **1-cycle pulse** — `UNLOCK_REQUEST` state auto-clears to `NO_REQUEST` after one clock.
- `unlock_req` drives `ThreeBitsCounter.sclr` directly in the wrapper → `locked` drops to 0.
- Supervisor stays in session after unlock; can choose next command (EXIT, change password, etc.).

### CHANGE USER / CHANGE SUPERVISOR PASSWORD (`change_user_req` / `change_super_req`)
- `supervisor_requests` enters `CHANGE_USER_PASSWORD` or `CHANGE_SUPERVISOR_PASSWORD` state and holds.
- Goes **deaf to `enter_d`** — all digit presses belong to `change_password.sv` while it runs.
- Waits for `cp_done` (`cp_complete | cp_fail`) from `change_password.sv`.
- On `cp_done=1` → returns to `NO_REQUEST`; supervisor can choose next command or EXIT.

### Edge cases handled

| Problem | Resolution |
|---|---|
| Using `access_state[2:0]` bus coupled `supervisor_requests` to `access_permission` internals | Replaced with `session_active` 1-bit signal; `supervisor_requests` knows nothing about AP state encoding |
| Single `cmd_request[2:0]` bus required encoding knowledge in receiving modules | Replaced with individual 1-bit signals routed directly to each destination |
| CHANGE_USER/SUPER held command continuously — would re-trigger `cp_start` every cycle | `supervisor_requests` goes deaf to `enter_d` in CHANGE states; `cp_done` is the only exit trigger |
| Password digits during change_password would be misread as supervisor commands | `supervisor_requests` does not check `enter_d` in CHANGE states; all digit presses go exclusively to `change_password.sv` |
| After UNLOCK, supervisor was stuck in UNLOCK_REQUEST state | `UNLOCK_REQUEST` auto-clears to `NO_REQUEST` after 1 cycle (pulse); supervisor can immediately choose next command |

---

## 7. Supervisor Cancel Password Change

### Flow
1. Supervisor selects CHANGE_USER or CHANGE_SUPER → `change_password.sv` starts.
2. Supervisor changes their mind during ENTRY phase.
3. Supervisor presses **1010** as the first digit entry → `change_password` ENTRY terminates immediately with only end-marker stored.
4. `change_password` VERIFY fails → `cp_fail=1` → `cp_done=1`.
5. `supervisor_requests` → `NO_REQUEST`.
6. Supervisor can now press EXIT (digit 2) or choose another command.

---

## 8. LED Feedback

| Event | Behaviour | Duration |
|---|---|---|
| Correct password | `Corr_LED` static ON | 3 000 ms (3 s), then off |
| Wrong password / error | `Err_LED` blinks 3× | 3 × (250 ms ON + 250 ms OFF) = 1 500 ms total |

Both outputs latch the 1-cycle pulse from `access_permission` (S6 and S5 respectively).
Implementation: FSM in `leds.sv` with 12-bit cycle counter at `clk1ms`. Status: **pending**.

---

## 9. Supervisor Timeout Alarm (pending)

If a key is inserted but the supervisor does not complete authentication within the alarm window, an alarm fires to signal a possible theft attempt or forgotten key.

- Trigger: `key=1`, FSM in S2, timer expires.
- Duration: TBD (10 s / 15 s / 30 s — see `md/DESIGN_SPECS.md` section 3).
- Alarm latches until cleared (clear condition TBD).
- Separate counter from user timeout counter.

---

## Signal Quick Reference

| Signal | Direction | Meaning |
|---|---|---|
| `session_active` | AP → supervisor_requests | Supervisor session (S3) is active |
| `exit_req` | supervisor_requests → wrapper | Supervisor selected EXIT; drives `srst_access` |
| `unlock_req` | supervisor_requests → wrapper | Supervisor selected UNLOCK; drives `ThreeBitsCounter.sclr` (1-cycle pulse) |
| `change_user_req` | supervisor_requests → lab_2 | Supervisor selected change user password |
| `change_super_req` | supervisor_requests → lab_2 | Supervisor selected change supervisor password |
| `cp_done` | change_password → supervisor_requests | Password change completed or aborted |
| `rst_failureCtr` | wrapper external input | Clears `ThreeBitsCounter`; driven by `unlock_req \| ap_rst_failureCtr` |
| `srst_access` | wrapper external input | Sync reset: AP FSM, lock_validation, codeStorage, timeout counter |
