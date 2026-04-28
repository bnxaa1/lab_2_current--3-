# User Flow

This document describes every user interaction path through the system, the expected outcomes, and the edge cases and problems that were identified and resolved for each path.

---

## Actors

| Actor | Description |
|---|---|
| **User** | Normal person entering a password to unlock the system |
| **Supervisor** | Trusted person holding the physical key; can unlock, change passwords |

---

## Keypad Layout

```
        Col 0  Col 1  Col 2  Col 3
 Row 0:   1      2      3      A   (unassigned)
 Row 1:   4      5      6      B   (unassigned)
 Row 2:   7      8      9      C   (unassigned)
 Row 3:   E      0      F      D   ← terminator
```

**Valid inputs:** digits `0–9` only.
**Terminator:** `D` (4'hD = 4'b1101) — confirms end of password entry.
**Unassigned:** `A, B, C, E, F` — currently treated as mismatches (see Section 10).
**Scanning:** `keypad_interface.sv` drives columns LOW and senses rows (Phase 1), then swaps direction to sense columns (Phase 2). Both `cols` and `rows` require external **pull-up resistors** to VCC — sensed lines must default HIGH when no key is pressed.

---

## 1. Normal User Authentication

### Flow

1. System is idle in **S0**. All LEDs off.
2. User presses first digit on the keypad.
   - `keypad_interface` scans the matrix, decodes the key, asserts `Enter` LOW (active-low) after debounce.
   - `one_pulse_generator` generates a single `enter_d` pulse (15 ms debounce at 1 kHz).
   - `access_permission` sees `input_cond = {locked=0, key=0, enter=1}` → S0 → **S1**; timeout counter resets to 0.
   - This first press is simultaneously the auth trigger AND the first digit — no separate start button.
3. User enters remaining digits. Each press:
   - `one_pulse_generator` debounces, produces `enter_d`.
   - `codeStorage` counter advances; RAM outputs the stored digit at `rStartingAddress + ctr`.
   - `lock_validation` compares RAM output (`code`) against `switches` — mismatch → FSM moves to S2 (silent mismatch state, waits for terminator).
4. User presses **D** (terminator, `4'hD`).
   - All digits matched → `correct=1` → S1 → **S6** → `Corr_LED` ON (4 s) → S0.
   - Any digit mismatched → `error=1` → S1 → **S5** → `Err_LED` blinks 3 × fast → S0; failure counter +1.
   - Early terminator (fewer digits than password length) → mismatch at terminator position → same error path.

### Edge cases handled

| Problem | Resolution |
|---|---|
| First digit press suppressed by `srst` in S0 | `srst` only asserted when `!enter`; LPM `sclr` has priority over `clk_en` — counter would freeze on press 1 without this guard |
| `correct`/`error` are 1-cycle pulses — level checks always miss them | Testbench uses `ev_correct`/`ev_error` edge-latching flags |
| Failure counter accumulated across testbench tests | `apply_reset` pulses `rst_failureCtr` after every error-generating test |

---

## 2. User Timeout

### Flow

1. User presses at least one digit → enters **S1**; timeout counter starts from 0.
2. User stalls — no further input for **5,000 ms** (5 s at 1 kHz).
3. `timeOut` fires → `access_permission` S1 → **S0**; `codeStorage` counter and `lock_validation` FSM reset via `rst_lv`.
4. `Err_LED` emits one **slow blink** (512 ms ON, 512 ms OFF) to indicate timeout.
5. No failure counter increment — timeout is not a wrong attempt.

### Edge cases handled

| Problem | Resolution |
|---|---|
| Timeout counter must start from 0 on every new auth attempt | `rst_timeoutCtr` fires only on S0→S1 transition; dedicated output of `access_permission` |
| Timeout counter was too narrow (20-bit at 50 MHz = 20 ms) | Replaced with `thirteenBitsCtr` (13-bit at 1 kHz = 5 s) |
| Session exit (`srst_access`) did not reset the timeout counter | `srst_access` added to `rst_timeoutCtr` OR chain in wrapper |
| Supervisor path must never timeout | `timeOut` only checked in S1 (user state); S2 and S3 ignore it |

---

## 3. System Lockout After 4 Failures

### Flow

1. User accumulates 4 wrong password attempts → `ThreeBitsCounter` reaches 4 → `locked=1`.
2. `Lock_LED` (LEDR[4]) turns ON and stays ON — steady red indicates locked state.
3. While locked, all user digit presses are blocked:
   - `enter_d` gate: `enter_d = enter_d_raw && (!locked || key)` — blocks `codeStorage` counter and `lock_validation` FSM advances.
   - `lock_validation` held in synchronous reset: `.srst(rst_lv | (locked && !key))` — FSM stays in S0, never compares digits.
4. No `error` pulse, no failure counter increment while locked — phantom failures cannot accumulate.
5. `Lock_LED` turns OFF only when supervisor unlocks (see Section 6 — UNLOCK command).

### Edge cases handled

| Problem | Resolution |
|---|---|
| `lock_validation` could still tick on `enter_d_raw` while locked, producing spurious `error` pulses | FSM held in synchronous reset via `.srst(rst_lv \| (locked && !key))`; never compares digits while locked |
| Gating `enter_al` instead of `enter_d` was considered | Rejected — masking `enter_al` at key insertion risks a spurious OPG pulse when the gate releases |
| `rst_failureCtr` hardwired to 0 — lockout was permanent | Connected to `ap_rst_failureCtr | unlock_req`; supervisor unlock and user correct both clear the counter |
| `ThreeBitsCounter.sclr` silently ignored when `increment=0` | LPM `clk_en` was connected to `increment` — `sclr` requires `clk_en=1`. Fixed by renaming port to `cnt_en` (count-only gate, does not block `sclr`); `clk_en` tied internally to `1'b1` |

---

## 4. Supervisor Key Interrupt During User Auth

### Flow

1. User is mid-entry in **S1**.
2. Supervisor inserts physical key (`key=1`).
3. `access_permission` S1: detects `key=1` → asserts `rst_lv=1` → resets `codeStorage` counter and `lock_validation` FSM → transitions to **S0**.
4. User entry is cleanly aborted; system returns to idle.
5. No failure count increment — key interrupt is not an error.

### Edge cases handled

| Problem | Resolution |
|---|---|
| Counter and FSM left in dirty state after key interrupt | `rst_lv=1` on S1 key detection resets both before S0 |

---

## 5. Supervisor Authentication

### Flow

1. Supervisor inserts physical key (`key=1`).
2. Supervisor presses first digit → `input_cond` matches `3'b011` (unlocked) or `3'b111` (locked) → S0 → **S2**.
   - `key` must remain HIGH for the entire S2 sequence; if `key` drops to 0 at any point → `rst_lv=1`, S2 → S0 (key-removal abort).
3. Supervisor enters password: `2, 0, 2, 6, D` (5 presses, D-terminated; RAM addr 32–36).
4. On `correct`:
   - → **S3** (supervisor session).
   - `Corr_LED` ON (4 s) — confirms successful authentication.
5. On `error` → **S5** → S0. No failure counter increment for supervisor wrong password.
6. Supervisor path has **no timeout** — S2 and S3 ignore `timeOut`.

### Edge cases handled

| Problem | Resolution |
|---|---|
| Supervisor password region was at addr 20 — inconsistent with `{key, active_bit, 4'b0000}` encoding | Moved to addr 32–36 (`key=1, active_bit=0, offset=0`) |
| `key` dropping briefly during supervisor digit entry would abort S2 | Testbench `enter_supervisor_digit` task forces `key_raw=1` throughout every press/release cycle |
| S3 and S4 were separate states requiring locked check on S2 exit | Merged into single S3; `locked` discriminates behaviour via `input_cond[2]` inside S3 |
| S3/S4 were dead-end states — no exit except `resetN` | Exit handled by `exit_req` from `supervisor_requests` driving `srst_access` |

---

## 6. Supervisor Session Commands

After reaching S3, the supervisor selects a command using a single digit press + enter. `supervisor_requests.sv` reads `enter_d` + `switches` while `session_active=1`.

| Digit | Command | Available when |
|---|---|---|
| `1` | Change user password | Always in S3 |
| `2` | Exit session → S0 | Always in S3 |
| `3` | Unlock system (clear failure counter) | Always in S3 (only useful when `locked=1`) |
| `4` | Change supervisor password | Always in S3 |

Each command maps to an individual 1-bit output: `exit_req`, `unlock_req`, `change_user_req`, `change_super_req`.

---

### EXIT (`exit_req`)

- `exit_req=1` drives `srst_access=1` at wrapper level.
- Resets: AP FSM → S0, `lock_validation` FSM, `codeStorage` counter, timeout counter.
- Does **NOT** reset failure counter.
- `session_active` drops to 0 → `supervisor_requests` auto-clears to `NO_REQUEST`.

---

### UNLOCK (`unlock_req`)

- `unlock_req` is a **1-cycle pulse** — `UNLOCK_REQUEST` state auto-clears to `NO_REQUEST` after one clock.
- `unlock_req` drives `ThreeBitsCounter.sclr` in the wrapper → counter → 0 → `locked=0` → `Lock_LED` OFF.
- `Corr_LED` ON (4 s) — confirms successful unlock.
- Supervisor stays in session after unlock; can immediately choose another command (EXIT, change password, etc.).

---

### CHANGE USER / CHANGE SUPERVISOR (`change_user_req` / `change_super_req`)

- `supervisor_requests` enters `CHANGE_USER_PASSWORD` or `CHANGE_SUPERVISOR_PASSWORD` state and **holds**.
- Goes **deaf to `enter_d`** while change is in progress — all keypresses belong to `change_password.sv`.
- Waits for `cp_done` (`cp_complete | cp_fail`) from `change_password.sv`.
- On `cp_done=1` → returns to `NO_REQUEST`; supervisor can choose next command or EXIT.
- On `cp_complete`: `Corr_LED` ON (4 s) — confirms password change success.

---

### Edge cases handled

| Problem | Resolution |
|---|---|
| `access_state[2:0]` bus coupling coupled `supervisor_requests` to AP internals | Replaced with `session_active` 1-bit signal |
| Single `cmd_request[2:0]` bus required encoding knowledge in receiving modules | Replaced with individual 1-bit signals routed directly to each destination |
| CHANGE states held command continuously — would re-trigger `cp_start` every cycle | `supervisor_requests` goes deaf to `enter_d` in CHANGE states |
| Password digits during change_password would be misread as supervisor commands | `supervisor_requests` does not check `enter_d` in CHANGE states |
| After UNLOCK, supervisor stuck in UNLOCK_REQUEST state | `UNLOCK_REQUEST` auto-clears to `NO_REQUEST` after 1 cycle |

---

## 7. Change Password

### Memory layout — double-buffer address swap

The RAM is 64 words × 4 bits (6-bit address). Address space split into 4 regions of 16 slots, encoded in `addr[5:4]`:

| `addr[5:4]` | Region | Addresses | Identity |
|---|---|---|---|
| `2'b00` | User region A | 0–15 | User (default active) |
| `2'b01` | User region B | 16–31 | User (swap target) |
| `2'b10` | Supervisor region A | 32–47 | Supervisor (default active) |
| `2'b11` | Supervisor region B | 48–63 | Supervisor (swap target) |

**Rationale for double-buffer over copy:** A COPY phase risks partial corruption if power is lost mid-copy — active password ends up half-new, half-old, system inaccessible. Address-swap never touches the active region during entry or verification. New password written entirely to inactive region first. On verified success, a single register bit flip makes it the active region — atomic, no mid-operation window.

**Address derivation:**
- `rStartingAddress = {key, key ? super_active : user_active, 4'b0000}`
  - Bit 5 (`key`) → user (0) or supervisor (1) region
  - Bit 4 (`active_bit`) → A (0) or B (1) region
- Inactive region: `target_addr = active_addr ^ 6'b010000` — flip bit 4 only

**Swap registers** (`user_active`, `super_active`) live in `access_permission_wrapper`. Both initialise to 0 (region A, matching `.mif`). On `cp_complete`, the relevant bit flips.

---

### FSM — 4 states

```
IDLE → ENTRY → VERIFY → DONE / ERROR
```

| State | Key outputs | Exit condition |
|---|---|---|
| IDLE | `cp_active=0` | `start=1` → Mealy: assert `ctrRst`, `srst_lv` → ENTRY |
| ENTRY | `srst_lv=1`, `wren=1`, `dataIn=switches` | `enter_d && (switches==4'hD \| done)` → Mealy: assert `ctrRst`, `srst_lv` → VERIFY |
| VERIFY | — | `lv_correct` → DONE; `lv_error` → ERROR |
| DONE | `cp_complete=1` (1 cycle) | → IDLE |
| ERROR | `cp_fail=1` (1 cycle) | → IDLE |

**`wren=1` continuously in ENTRY (not gated by `enter_d`):** Altsyncram write port has registered inputs — if `wren` were gated by the 1-cycle `enter_d` pulse, the write would complete one cycle after the pulse on an unstable `switches` value. With `wren=1` always, the RAM continuously captures `switches` on every cycle. The counter only advances on `enter_d`. The last write before counter advance captures the confirmed digit exactly at the `enter_d` clock edge.

**`srst_lv=1` throughout ENTRY:** Prevents `lock_validation` from reading the inactive RAM region while it is being written to. Simultaneous read-write on the same address with `READ_DURING_WRITE=DONT_CARE` produces undefined output. Holding `lock_validation` in reset eliminates this conflict.

---

### Happy path

1. Supervisor in S3 presses `1` → `change_user_req=1` → `start=1`.
2. IDLE detects `start`: Mealy asserts `ctrRst=1`, `srst_lv=1` → ENTRY (ctr=0, lock_validation reset).
3. ENTRY: supervisor types new password e.g. `5,7,3,D` — digits written to inactive region (addr 16–18 for user B). `srst_lv=1` keeps lock_validation deaf; `wren=1` continuously armed.
4. `D` detected: Mealy asserts `ctrRst=1`, `srst_lv=1` → VERIFY (ctr=0, lock_validation reset, read address now points to inactive region).
5. VERIFY: supervisor re-enters `5,7,3,D` — `lock_validation` reads from inactive region and compares; `lv_correct=1`.
6. DONE: `cp_complete=1` (1 cycle) → wrapper flips `user_active` → region B becomes active user password. `Corr_LED` ON (4 s).
7. `supervisor_requests` sees `cp_done=1` → NO_REQUEST; supervisor can EXIT or issue another command.

---

### Verification mismatch

1. ENTRY: supervisor types `5,7,3,D` → written to inactive region.
2. VERIFY: supervisor re-enters `5,7,9,D` — mismatch on digit 3 → `lv_error=1`.
3. ERROR: `cp_fail=1` → `supervisor_requests` → NO_REQUEST.
4. **Active region untouched throughout.** Old password remains valid.

---

### Cancel (press D immediately)

1. ENTRY: supervisor presses `D` as the very first key — only `D` is written to inactive region at offset 0.
2. Mealy transition → VERIFY with ctr=0.
3. VERIFY: supervisor types any real digit → lock_validation compares against a region containing only `D` at position 0 → immediate mismatch → `lv_error`.
4. ERROR: `cp_fail=1` → NO_REQUEST; active region never touched.

---

### Edge cases handled

| Problem | Resolution |
|---|---|
| Power failure during COPY would corrupt active password | COPY phase eliminated; address-swap is atomic |
| `wren` gated by `enter_d` risks missing digit if `switches` changes after pulse | `wren=1` continuously in ENTRY |
| `lock_validation` could read inactive region during ENTRY (read-during-write undefined) | `srst_lv=1` throughout ENTRY holds lock_validation in reset |
| `cp_complete` on failure would swap region to a bad password | Separate `cp_fail` releases `supervisor_requests` without triggering address swap |
| `start` held high could re-trigger `change_password` | `change_password` only checks `start` in IDLE |

---

## 8. Supervisor Cancel Password Change

### Flow

1. Supervisor selects CHANGE_USER or CHANGE_SUPER → `change_password` ENTRY starts.
2. Supervisor changes their mind — presses **D** as the very first digit in ENTRY.
3. ENTRY terminates immediately → VERIFY with only `D` at offset 0 in inactive region.
4. VERIFY: any real digit entry → immediate `lv_error` → `cp_fail=1` → `cp_done=1`.
5. `supervisor_requests` → NO_REQUEST.
6. Supervisor can now press EXIT (digit 2) or choose another command.

---

## 9. LED Feedback

### Full behaviour table

| Event | `Corr_LED` | `Err_LED` | `Lock_LED` |
|---|---|---|---|
| Correct user auth | ON steady 4 s | — | unchanged |
| Correct supervisor auth | ON steady 4 s | — | unchanged |
| Password change success | ON steady 4 s | — | unchanged |
| Supervisor unlock | ON steady 4 s | — | turns OFF |
| Wrong password (user or supervisor) | — | 3 × fast blink (256 ms ON / 256 ms OFF) | unchanged |
| Session timeout | — | 1 × slow blink (512 ms ON / 512 ms OFF) | unchanged |
| System locked (`locked=1`) | — | — | ON steady (until unlocked) |
| System locked + supervisor wrong password | — | 3 × fast blink | stays ON |
| System unlocked (lock cleared) | ON steady 4 s | — | turns OFF |

### Implementation

`leds.sv` FSM with a single `twelveBitsCounter` LPM instance (`sclr` driven by `ctr_rst`):

| Timing check | Counter bit | Duration at 1 kHz |
|---|---|---|
| Wrong password blink phase | `ctr[8]` | 256 ms |
| Timeout blink phase | `ctr[9]` | 512 ms |
| Correct hold | `&ctr` (all 12 bits = 1) | 4,096 ms ≈ 4 s |

**States:** `IDLE → CORR_HOLD` for correct events; `IDLE → BLINK_ON → BLINK_OFF` (×3) for wrong password; `IDLE → TIMEOUT_ON → TIMEOUT_OFF` for timeout. `Lock_LED` is a combinational assignment (`Lock_LED = locked_in`) — independent of the FSM.

**`Corr_LED` sources (all OR into `corr_in`):**
- `ap_corr_pulse` — user correct auth (access_permission S6)
- `sup_corr_pulse` — supervisor correct auth (rising edge of `session_active`)
- `cp_complete` — password change verified
- `unlock_req` — supervisor unlock executed

---

## 10. Input Range Validation (pending)

### Problem

Keys `A, B, C, E, F` are physically accessible on the keypad but have no role in the password scheme. Pressing one during authentication:
- Causes an immediate mismatch (these values are never stored as passwords).
- If D is then pressed to terminate, counts as a wrong attempt.
- 4 such accidents → system locked.

During `change_password` ENTRY, these keys are written to RAM and create passwords that are unreproducible under the intended digit-only convention.

### Planned fix

Gate `enter_d` behind a validity check before it reaches `lock_validation` and `change_password`:

```sv
valid_input = (switches <= 4'd9) || (switches == 4'b1101); // 0-9 or D
```

Invalid keypresses are silently ignored — no mismatch, no counter advance, no RAM write. The user simply sees no response, as if the key was never pressed.

---

## 11. Supervisor Timeout Alarm (pending)

If a key is inserted but the supervisor does not complete authentication within the alarm window, an alarm fires to signal a possible theft attempt or forgotten key.

- Trigger: `key=1`, FSM in S2, timer expires.
- Duration: TBD (10 s / 15 s / 30 s).
- Alarm latches until cleared (clear condition TBD).
- Separate counter from user timeout counter.

---

## Signal Quick Reference

| Signal | Direction | Meaning |
|---|---|---|
| `session_active` | AP → supervisor_requests | Supervisor session (S3) is active |
| `exit_req` | supervisor_requests → wrapper | Supervisor selected EXIT; drives `srst_access` |
| `unlock_req` | supervisor_requests → wrapper | Supervisor selected UNLOCK; 1-cycle pulse; drives `ThreeBitsCounter.sclr` |
| `change_user_req` | supervisor_requests → lab_2 | Supervisor selected change user password |
| `change_super_req` | supervisor_requests → lab_2 | Supervisor selected change supervisor password |
| `cp_done` | lab_2 (combinatorial) | `cp_complete \| cp_fail`; releases supervisor_requests from CHANGE state |
| `srst_access` | wrapper external input | Sync reset: AP FSM, lock_validation, codeStorage, timeout counter |
| `cp_complete` | change_password → wrapper | Password verified; triggers `user_active`/`super_active` bit flip (address swap) |
| `cp_fail` | change_password → cp_done | Password mismatch or cancel; releases supervisor_requests without swapping |
| `cp_active` | change_password → wrapper | Overrides `rStartingAddress`/`wStartingAddress` to `target_addr` during change |
| `target_addr` | change_password → wrapper | Inactive region address: `active_addr ^ 6'b010000` (bit 4 flipped) |
| `active_addr` | wrapper → change_password | Pre-mux active region start: `{key, active_bit, 4'b0000}` |
| `is_supervisor` | lab_2 → wrapper | `change_super_req`; tells wrapper which register to flip on `cp_complete` |
| `cp_ctrRst` | change_password → wrapper → lvw | Mealy reset on IDLE→ENTRY and ENTRY→VERIFY; resets codeStorage counter |
| `cp_srst_lv` | change_password → wrapper → lvw | Mealy reset on IDLE→ENTRY and ENTRY→VERIFY; resets lock_validation FSM |
| `done` | lock_validation_wrapper → lab_2 | codeStorage counter at 9 (max 10 digits); guards ENTRY exit in change_password |
| `enter_d` | wrapper → lab_2 | Gated debounced keypress; shared by supervisor_requests and change_password |
| `timeOut` | wrapper → lab_2 | 1-cycle pulse when 13-bit timeout counter reaches 5,000 |
| `locked` | wrapper → lab_2 | Level: ThreeBitsCounter == 4 |
| `user_active` | wrapper internal | 0 = region A active, 1 = region B active; flipped on cp_complete for user |
| `super_active` | wrapper internal | 0 = region A active, 1 = region B active; flipped on cp_complete for supervisor |
| `ap_corr_pulse` | lab_2 internal | 1-cycle pulse from access_permission S6 (user correct) → leds corr_in |
| `ap_err_pulse` | lab_2 internal | 1-cycle pulse from access_permission S5 (wrong password) → leds err_in |
| `sup_corr_pulse` | lab_2 internal | Rising edge of `session_active` → leds corr_in (supervisor auth confirmation) |
| `Lock_LED` | lab_2 output → LEDR[4] | Steady ON while system locked; combinational: `Lock_LED = locked` |
| `Err_LED` | lab_2 output → LEDR[2] | Blinks on wrong password (fast) or timeout (slow) |
| `Corr_LED` | lab_2 output → LEDR[3] | 4 s steady on correct auth, unlock, or password change success |
| `error` | lab_2 output → LEDR[0] | Raw 1-cycle error pulse from lock_validation |
| `correct` | lab_2 output → LEDR[1] | Raw 1-cycle correct pulse from lock_validation |
