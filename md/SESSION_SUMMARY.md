# Session Summary — access_permission_wrapper

> **Note:** This document reflects the system state after multiple development sessions. Earlier sections describe architectural decisions; the simulation results at the bottom are outdated and superseded by the full-system testbench (`tb_lab_2.sv`).

---

## System user flow

### Normal user authentication
1. User approaches the lock panel. System is idle in **S0**.
2. User presses the first digit on the keypad (`switches` + `enter_al` pulse).
   - This is the auth trigger — there is no separate start button.
   - `access_permission` transitions S0 → S1; timeout counter resets to 0.
3. User enters the remaining digits one at a time. Each press:
   - `one_pulse_generator` debounces the press (15 ms window at 1 kHz).
   - `codeStorage` counter advances; the digit at `rStartingAddress + ctr` is compared to `switches` by `lock_validation`.
4. User presses the **end marker** (switches = `4'hD`, the `D` key — bottom-right of keypad).
   - If all digits matched: `correct=1` → S1 → S6 → Corr_LED ON → S0.
   - If any digit mismatched: `error=1` → S1 → S5 → Err_LED ON → S0; failure counter +1.
5. After **4 failures** the system locks (`locked=1`). User entry is fully blocked — no LED feedback, no counter advance.

### Supervisor authentication
1. Supervisor inserts the physical key (`key=1`).
2. Supervisor presses the first digit. System transitions S0 → S2 regardless of `locked`.
   - **`key` must remain high for the entire S2 sequence** — if key drops to 0 at any point, S2 → S0 immediately (key-removal abort).
3. Supervisor enters the full password (`2, 0, 2, 6, D` — 5 presses, D-terminated).
4. On `correct`:
   - System transitions S2 → **S3** (supervisor session; both locked and unlocked handled in S3 via `input_cond[2]`).
5. In S3, supervisor enters a single-digit command via `supervisor_requests`:
   - `1` = change user password, `2` = exit, `3` = unlock, `4` = change supervisor password
   - `exit_req` drives `srst_access` → FSM returns to S0.

### Timeout
- If the user enters at least one digit but stalls in S1 for 5 000 ms (5 s), `timeOut` fires.
- `access_permission` S1 → S0; `codeStorage` counter and `lock_validation` FSM reset via `rst_lv`.
- Supervisor path (S2) has no timeout.

---

## Key architectural fixes made (across all sessions)

### 1 — lock_validation_wrapper.sv: `.srst(rst_lv | (locked && !key) | cp_srst_lv)`
**Why:** While locked and no supervisor key, `lock_validation`'s FSM could still transition on `enter_d_raw`, causing `error` to fire and increment the failure counter.
**Fix:** Hold `lock_validation` in synchronous reset whenever `locked && !key`. Also gate `enter_d = enter_d_raw && (!locked || key)`.

### 2 — access_permission_wrapper.sv: address regions moved to 6-bit double-buffer scheme
**Why:** Original scheme used 5-bit addresses pointing to fixed regions. Password change required physically overwriting the active region.
**Fix:** 6-bit address: bit 5 = key (user/supervisor), bit 4 = region swap bit (A/B). Four 16-slot regions. `user_active`/`super_active` flip on `cp_complete`.

### 3 — ThreeBitsCounter.v: `clk_en` → `cnt_en`
**Why:** Altera LPM `sclr` only fires when `clk_en=1`. Connecting `clk_en` to `increment` blocked `sclr` when `increment=0` — supervisor unlock couldn't clear the failure counter.
**Fix:** Port renamed to `cnt_en`; `clk_en=1'b1` tied internally. `sclr` fires unconditionally.

### 4 — user_active/super_active: removed resetN reset
**Why:** Password changes were lost on `resetN` restart. Reset should restart the session, not factory-reset the password.
**Fix:** Registers now have no `negedge resetN` — they only change on `cp_complete`.

### 5 — Terminator changed from `A` (`4'hA`) to `D` (`4'hD`)
**Why:** `A` is the top-right key — unintuitive. `D` is the bottom-right key — natural confirm position.
**Fix:** Updated in `lock_validation.sv`, `change_password.sv`, `ram_sim.v`, `ramm.mif`, all testbenches.

---

## Quick reference

| Item | Value |
|---|---|
| User password (default) | `1, 2, 3, 4, D` — RAM addr 0–4 |
| Supervisor password (default) | `2, 0, 2, 6, D` — RAM addr 32–36 |
| `rStartingAddress` user A | `6'b000000` (0) |
| `rStartingAddress` supervisor A | `6'b100000` (32) |
| Clock | 1 kHz (`clk1ms`); TB drives it directly |
| Debounce window | 15 cycles = 15 ms |
| Digit press timing | 20 press + 25 release = 45 cycles per digit |
| Timeout | 5 000 cycles = 5 s (user S1 only) |
| Lock threshold | `ThreeBitsCounter == 4` |
| `enter_d` gate | `enter_d_raw && (!locked \| key)` |
| `lock_validation` srst | `rst_lv \| (locked && !key) \| cp_srst_lv` |
| `effective_rst_lv` | `rst_lv \| srst_access` |
| Terminator key | `D` = `4'hD` = `4'b1101` = 13 |
