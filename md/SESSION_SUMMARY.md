# Session Summary — access_permission_wrapper

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
4. User presses the **end marker** (switches = `1010`).
   - If all digits matched: `correct=1` → S1 → S6 → Corr_LED ON → S0.
   - If any digit mismatched: `error=1` → S1 → S5 → Err_LED ON → S0; failure counter +1.
5. After **4 failures** the system locks (`locked=1`). User entry is fully blocked — no LED feedback, no counter advance.

### Supervisor authentication
1. Supervisor inserts the physical key (`key=1`).
2. Supervisor presses the first digit. System transitions S0 → S2 regardless of `locked`.
   - **`key` must remain high for the entire S2 sequence** — if key drops to 0 at any point, S2 → S0 immediately (key-removal abort).
3. Supervisor enters the full password (`2, 0, 2, 6, 1010` — 5 presses, end-marker terminated).
4. On `correct`:
   - System not locked → S2 → **S3** (supervisor session, normal).
   - System locked → S2 → **S4** (supervisor session, locked-system path).
5. S3/S4 are currently dead-end states; exit transitions are a pending task.

### Timeout
- If the user enters at least one digit but stalls in S1 for 5 000 ms (5 s), `timeOut` fires.
- `access_permission` S1 → S0; `codeStorage` counter and `lock_validation` FSM reset via `rst_lv`.
- Supervisor path (S2) has no timeout.

---

## Changes made this session and why

### 1 — lock_validation_wrapper.sv: `.srst(rst_lv | (locked && !key))`
**Why:** Gating `enter_d` (the clock-enable to `codeStorage`) prevented the counter from advancing while locked, but `lock_validation`'s internal FSM could still transition on `enter_d_raw` (the ungated pulse from `one_pulse_generator`). This caused `error` to fire even when the user was blocked, which incremented the failure counter and produced false LED feedback.

**Fix:** Hold `lock_validation` in synchronous reset whenever `locked && !key`. The FSM stays in S0, never compares digits, never asserts `error` or `correct`. Enter-al gating was rejected because masking `enter_al` when the supervisor inserts the key risks a spurious debounce pulse at the moment the gate is released.

---

### 2 — access_permission_wrapper.sv: `rStartingAddress` supervisor → addr 20
**Why:** The RAM was updated so the supervisor password region starts at address 20 (previously 10). The old address `5'b01010` pointed to the wrong RAM region — supervisor auth would compare against zeros instead of the actual password `2, 0, 2, 6, 10`.

**Fix:** `assign rStartingAddress = key ? 5'b10100 : 5'b00000;`

---

### 3 — ramm.mif: supervisor region moved to addr 20–24
**Why (user-initiated):** Supervisor password region reorganised to start at addr 20. New content: `2, 0, 2, 6, 10` (end-marker at addr 24). Same end-marker termination style as the user region — auth ends when `switches == 1010` and `code == 1010` match, not via `done` counter.

---

### 4 — tb_access_permission_wrapper.sv: event flags (`ev_correct`, `ev_error`, …)
**Why:** `correct`, `error`, `Corr_LED`, `Err_LED` are 1-clock pulses. The `repeat(4)` wait after digit entry ran for 4 ms — long after the pulse had returned to 0. Every level-based check read 0 and reported FAIL even when the pulse fired correctly.

**Fix:** `always @(posedge signal)` blocks latch each pulse into `ev_*` flags. `clear_ev` is called before each test. Checks use `ev_*` instead of live signals.

---

### 5 — tb: `apply_reset` after error-generating tests (2, 3, 4, 5)
**Why:** `sync_reset` resets the AP FSM and `codeStorage` counter via `srst_access`, but it does NOT touch `ThreeBitsCounter` (no `aclr` port on the LPM IP). After tests 2, 3, 4, 5 each generate one `error` → `increment`, the failure counter accumulated to 4 by test 5 and the system locked mid-sequence — corrupting tests 6, 7, 8 that followed.

**Fix:** Use `apply_reset` (pulses `rst_failureCtr` after `resetN` release) after every test that intentionally generates an error. Use `sync_reset` only for tests that end with `correct` or a clean abort (tests 1, 6, 7, 8).

---

### 6 — tb: `enter_supervisor_digit` task + `key_to_dut` mux
**Why:** For supervisor authentication, `key` must stay at 1 for the entire S2 digit entry sequence. Using plain `enter_digit` with `key=1` set beforehand is fragile — any race or inadvertent assignment between tasks could drop `key` briefly, causing S2 → S0 abort and a reset of `codeStorage`, making the next digit compare against the wrong RAM address.

**Fix:**
- `enter_supervisor_digit` explicitly sets `key_raw=1` before, during, and after every press/release cycle.
- `assign key_to_dut = locked ? 1'b1 : key_raw;` — once the system is locked, `key` is forced high at the DUT input unconditionally. This models the real-world requirement that only the supervisor (who physically holds the key) can interact with a locked system.

---

## Simulation results (last run)

| Test | Result | Notes |
|---|---|---|
| 1 — correct user password | **PASS** | |
| 2 — wrong first digit | **PASS** | |
| 3 — correct digits, wrong end-marker | **PASS** | Two errors in log — second is a new auth started by the trailing 1010 press after FSM already reset to S0; expected behaviour |
| 4 — early end marker | **PASS** | |
| 5 — first correct, second wrong | **FAIL** | Re-run needed with latest TB fixes |
| 6 — key interrupt mid-entry, recovery | **FAIL** | Re-run needed |
| 7 — supervisor key removal, recovery | **FAIL** | Re-run needed |
| 8 — srst_access mid-entry, recovery | **FAIL** | Re-run needed |
| 9 — 4 failures → locked | **PASS** | |
| 9b — supervisor auth while locked → S4 | **PASS** | `key_to_dut` mux + `enter_supervisor_digit` confirmed working |
| 10 — timeout | **PASS** | |
| 11 — supervisor auth (not locked) → S3 | **FAIL** | `enter_supervisor_digit` applied; re-run needed |
| 12 — supervisor auth while locked → S4 | **FAIL** | `enter_supervisor_digit` applied; re-run needed |

---

## Pending tasks

| Task | File | Detail |
|---|---|---|
| S3/S4 exit transitions | `access_permission.sv` | Supervisor session currently dead-end; need key-removal → S0 |
| `rst_failureCtr` wiring | `lab_2.sv` | Hardwired to 0; needs `supervisor_unlock \| user_correct_pulse` |
| LED output logic | `leds.sv` | `corr_led_out` / `err_led_out` not driven |
| Top-level integration | `lab_2.sv` | Instantiate `change_password` + `supervisor_requests`; add muxes |
| Supervisor timeout alarm | `access_permission.sv` / wrapper | ~10 s alarm if supervisor doesn't complete auth |

---

## Quick reference

| Item | Value |
|---|---|
| User password | `1, 2, 3, 4, 1010` — RAM addr 0–4 |
| Supervisor password | `2, 0, 2, 6, 1010` — RAM addr 20–24 |
| `rStartingAddress` user | `5'b00000` (0) |
| `rStartingAddress` supervisor | `5'b10100` (20) |
| Clock | 1 kHz (`clk1ms`); TB drives it directly |
| Debounce window | 15 cycles = 15 ms |
| Digit press timing | 20 press + 20 release = 40 ms per digit |
| Timeout | 5 000 cycles = 5 s (user S1 only) |
| Lock threshold | `ThreeBitsCounter == 4` |
| `enter_d` gate | `enter_d_raw && (!locked \| key)` |
| lock_validation srst | `rst_lv \| (locked && !key)` |
| `effective_rst_lv` | `rst_lv \| srst_access` |
