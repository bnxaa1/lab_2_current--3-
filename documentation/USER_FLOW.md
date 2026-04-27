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
| Supervisor password region was at addr 20; moved to addr 32 for clean MSB encoding | `ramm.mif` addr 32–36 holds `2,0,2,6,1010`; `rStartingAddress = {key, active_bit, 4'b0000}` so addr[5]=key, addr[4]=region select |
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

## 7. Change Password

### Memory layout — double-buffer address-swap

The RAM is 64 words × 4 bits (256 bits total, 6-bit address). The address space is split into 4 regions of 16 slots each, encoded in `addr[5:4]`:

| addr[5:4] | Region | Addresses | Identity |
|---|---|---|---|
| `2'b00` | User region A | 0–15 | User (default active) |
| `2'b01` | User region B | 16–31 | User (swap target) |
| `2'b10` | Supervisor region A | 32–47 | Supervisor (default active) |
| `2'b11` | Supervisor region B | 48–63 | Supervisor (swap target) |

**Rationale for double-buffer over copy:**
A COPY phase (write new password over active region) risks partial corruption if power is lost mid-copy — the active password ends up half-new, half-old and the system becomes inaccessible. The address-swap approach never touches the active region during entry or verification. The new password is written entirely to the inactive region first. On verified success, a single register bit flip makes it the active region. This is atomic — no mid-operation window.

**Address derivation:**
- Active region: `rStartingAddress = {key, key ? super_active : user_active, 4'b0000}`
  - `key` (bit 5) selects user vs supervisor
  - `user_active` / `super_active` (bit 4) selects A (0) or B (1)
- Inactive region: `target_addr = active_addr ^ 6'b010000` — flip bit 4 only
- Both regions hold up to 10 digits (counter 0–9 ≤ 15); no overflow into adjacent region

**Swap registers** (`user_active`, `super_active`) live in `access_permission_wrapper`. Both initialise to 0 (region A, matching `.mif`). On `cp_complete`, the relevant bit flips.

---

### FSM — 5 states (reduced from original 8)

```
IDLE → ENTRY → VERIFY → DONE / ERROR
```

**Removed states and rationale:**
- `ENTRY_RST` removed: reset signals (`ctrRst`, `srst_lv`) became **Mealy outputs** on the IDLE→ENTRY transition. No dedicated cycle needed — they fire on the same cycle `start` is detected.
- `VERIFY_RST` removed: same — `ctrRst` and `srst_lv` fire as Mealy outputs on the ENTRY→VERIFY transition (the terminator/done cycle).
- `VERIFY_WAIT` removed: originally inserted to absorb the 1-cycle RAM registered-output latency after resetting the read address. Eliminated because `lock_validation` only makes a comparison when `enter_d` fires. The first keypress in VERIFY is always ≥ 15 ms (debounce) after VERIFY starts — the RAM output settles in 1 cycle, so the natural delay from waiting for the first keypress is always sufficient.
- `COPY_PREP`, `COPY_WAIT1`, `COPY_WAIT2`, `COPY` removed entirely: the address-swap approach replaces the copy phase.

**LPM counter note on Mealy resets:** when the terminator press fires both `ctrRst=1` (from Mealy) and `clk_en_override=1` (enter_d active) simultaneously, LPM `sclr` has priority over `clk_en` — counter resets to 0, not advances. Correct behaviour.

---

### State details

| State | Key outputs | Condition to exit |
|---|---|---|
| IDLE | `cp_active=0` | `start=1` → assert `ctrRst`, `srst_lv` (Mealy), → ENTRY |
| ENTRY | `srst_lv=1`, `wren=1`, `dataIn=switches` | `enter_d && (switches==1010 \| done)` → assert `ctrRst`, `srst_lv` (Mealy), → VERIFY |
| VERIFY | — | `lv_correct` → DONE; `lv_error` → ERROR |
| DONE | `cp_complete=1` (1 cycle) | → IDLE |
| ERROR | `cp_fail=1` (1 cycle) | → IDLE |

**`wren=1` continuously in ENTRY (not gated by `enter_d`):**
The Altera altsyncram write port has registered inputs — `wren`, `wraddress`, and `data` are latched at the rising clock edge. If `wren=1` were gated by `enter_d` (1-cycle pulse), the write would complete one cycle after `enter_d` goes low, relying on `switches` being stable at that later edge. Instead, `wren=1` always in ENTRY: the RAM continuously writes the current `switches` value to the current counter address. The counter only advances on `enter_d`. The last write before counter advance captures the confirmed digit exactly at the `enter_d` clock edge — no reliance on post-edge stability.

**`srst_lv=1` throughout ENTRY:**
Prevents `lock_validation` from reading the inactive RAM region while it is being written to. Simultaneous read and write on the same address with `READ_DURING_WRITE = DONT_CARE` produces undefined output. Holding `lock_validation` in reset eliminates this conflict entirely.

**`cp_complete` vs `cp_fail`:**
Both release `supervisor_requests` from the CHANGE state (`cp_done = cp_complete | cp_fail`). They differ in effect: `cp_complete` also triggers the address bit flip in the wrapper. Using `cp_complete` for failures would incorrectly swap the active region to a region containing a bad password.

**`is_supervisor`:**
Driven directly from `change_super_req` (level signal, stable throughout the change session). On `cp_complete`, the wrapper checks `is_supervisor` to decide whether to flip `user_active` or `super_active`.

**`start` is a level signal, not a pulse:**
`change_user_req` and `change_super_req` are level outputs of `supervisor_requests` (high while in CHANGE state). `start = change_user_req | change_super_req`. `change_password` only checks `start` in IDLE — once it leaves IDLE it never re-enters until DONE or ERROR, so the held-high level causes no re-triggering.

---

### Scenario 1 — Happy path

1. Supervisor in S3 presses digit `1` → `change_user_req=1` → `start=1`
2. IDLE detects `start`: Mealy asserts `ctrRst=1`, `srst_lv=1`; → ENTRY (ctr=0, lock_validation reset)
3. ENTRY: supervisor types new password e.g. `5,7,3,1010` — each digit written to inactive region (e.g. addr 16–19 for user region B). `srst_lv=1` keeps lock_validation deaf; `wren=1` armed continuously
4. Terminator `1010` detected: Mealy asserts `ctrRst=1`, `srst_lv=1`; → VERIFY (ctr=0, lock_validation reset)
5. VERIFY: supervisor re-enters `5,7,3,1010` — `lock_validation` reads from inactive region and compares; `lv_correct=1`
6. DONE: `cp_complete=1` (1 cycle) → wrapper flips `user_active` bit → inactive region (addr 16) becomes the new active user password region
7. `supervisor_requests` sees `cp_done=1` → NO_REQUEST; supervisor can EXIT or issue another command

---

### Scenario 2 — Verification mismatch

1. ENTRY: supervisor types `5,7,3,1010` → written to inactive region
2. VERIFY: supervisor re-enters `5,7,9,1010` — mismatch on digit 3 → `lv_error=1`
3. ERROR: `cp_fail=1` → `supervisor_requests` → NO_REQUEST
4. **Active region untouched throughout.** Old password remains valid
5. Inactive region holds the failed entry — harmless; overwritten on next change attempt

---

### Scenario 3 — Cancel (press 1010 immediately)

1. ENTRY: supervisor presses `1010` as the very first digit — only the end-marker is written to inactive region at offset 0
2. Mealy transition fires → VERIFY with ctr=0
3. VERIFY: supervisor types any real digit sequence → lock_validation compares against a region containing only `1010` at position 0 → immediate `lv_error`
4. ERROR: `cp_fail=1` → NO_REQUEST; active region never touched

---

### Scenario 4 — Max digits reached

1. ENTRY: supervisor enters 9 digits without pressing `1010` — `done=1` fires (codeStorage `ctr==9`)
2. Mealy transition fires on the 9th press (when `done=1`) → VERIFY
3. Continues normally; supervisor must re-enter the same 9 digits in VERIFY

---

### Edge cases handled

| Problem | Resolution |
|---|---|
| Power failure during COPY would corrupt active password | COPY phase eliminated; address-swap is atomic (single register flip) |
| COPY_WAIT and VERIFY_RST states added unnecessary latency | Removed; Mealy resets fire on the transition cycle itself; VERIFY_WAIT eliminated by natural keypress delay |
| `wren` gated by `enter_d` risks missing digit if switches changes after pulse | `wren=1` continuously in ENTRY; RAM writes current switches on every cycle; last write before counter advance is the confirmed digit |
| lock_validation could read inactive region during ENTRY (read-during-write undefined) | `srst_lv=1` throughout ENTRY holds lock_validation in reset; no reads from inactive region during writes |
| `cp_complete` firing on failure would swap region to a bad password | Separate `cp_fail` signal releases `supervisor_requests` without triggering the address swap |
| `start` held high by `supervisor_requests` could re-trigger `change_password` | `change_password` only checks `start` in IDLE; once in ENTRY or later, `start` is ignored |
| `ctrRst` and `clk_en_override` simultaneous on terminator press | LPM `sclr` has priority over `clk_en`; counter resets to 0, does not advance |

---

## 8. Supervisor Cancel Password Change

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
Implementation: FSM in `leds.sv` with a single 12-bit cycle counter at `clk1ms`. No magic number comparisons — `ctr[8]` naturally goes high after 256 cycles (≈250 ms) for blink timing; `&ctr` (all bits 1) fires after 4 096 cycles (≈4 s) for correct hold. States: `IDLE → CORR_HOLD` for correct; `IDLE → BLINK_ON → BLINK_OFF` (×3) for error. `blink_cnt_reg` (2-bit) tracks completed blink pairs.

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
| `cp_complete` | change_password → wrapper | Password verified; triggers `user_active`/`super_active` bit flip (address swap) |
| `cp_fail` | change_password → supervisor_requests (via cp_done) | Password mismatch or cancel; releases supervisor_requests to NO_REQUEST without swapping |
| `cp_done` | lab_2 (combinatorial) | `cp_complete \| cp_fail`; releases supervisor_requests from CHANGE state |
| `cp_active` | change_password → wrapper | Overrides `rStartingAddress`/`wStartingAddress` to `target_addr` during change |
| `target_addr` | change_password → wrapper | Inactive region address: `active_addr ^ 6'b010000` (bit 4 flipped) |
| `active_addr` | wrapper → change_password | Pre-mux active region start: `{key, active_bit, 4'b0000}` |
| `is_supervisor` | lab_2 → wrapper | `change_super_req`; tells wrapper which register to flip on `cp_complete` |
| `cp_ctrRst` | change_password → wrapper → lvw | Mealy reset on IDLE→ENTRY and ENTRY→VERIFY; resets codeStorage counter only |
| `cp_srst_lv` | change_password → wrapper → lvw | Mealy reset on IDLE→ENTRY and ENTRY→VERIFY; resets lock_validation FSM only |
| `done` | lock_validation_wrapper → wrapper → lab_2 | codeStorage counter at 9 (max 10 digits entered); guards ENTRY exit |
| `enter_d` | wrapper → lab_2 | Gated debounced keypress; shared by supervisor_requests and change_password |
| `user_active` | wrapper internal | 1-bit register; 0=region A active, 1=region B active; flipped on cp_complete for user |
| `super_active` | wrapper internal | 1-bit register; 0=region A active, 1=region B active; flipped on cp_complete for supervisor |
