# LED & HEX Display Guide

## LEDR Map

| LED | Signal | Type | Meaning |
|-----|--------|------|---------|
| `LEDR[0]` | `error` | 1-cycle pulse | Raw wrong-digit result from lock_validation |
| `LEDR[1]` | `correct` | 1-cycle pulse | Raw correct-password result from lock_validation |
| `LEDR[2]` | `Err_LED` | FSM-driven | Error feedback: blinks 3× on wrong attempt; steady on timeout |
| `LEDR[3]` | `Corr_LED` | FSM-driven | Correct feedback: holds on ~4 s after successful auth or password change |
| `LEDR[4]` | `Lock_LED` | Level | System locked — 4 consecutive failures; cleared by supervisor unlock |
| `LEDR[5]` | `SW[0]` | Level | Supervisor key active — on when SW[0] is up |
| `LEDR[8:6]` | `sr_state[2:0]` | 3-bit binary | Supervisor request state (see table below) |
| `LEDR[9]` | `session_active` | Level | Supervisor session active |

### `sr_state` Encoding (LEDR[8:6])

| Binary | Decimal | State |
|--------|---------|-------|
| `000` | 0 | Idle — no request pending |
| `001` | 1 | Changing user password |
| `010` | 2 | Changing supervisor password |
| `011` | 3 | Exit requested |
| `100` | 4 | Unlock requested (1-cycle pulse — see reliability note) |

---

## HEX Map

| Display | Content | Description |
|---------|---------|-------------|
| `HEX5` | `dbg_code` | RAM dataOut — digit being compared against switches |
| `HEX4` | `dbg_switches` | Last keypad digit pressed |
| `HEX3` | `dbg_rAddr[3:0]` | Low nibble of current read start address |
| `HEX2` | `{1'b0, dbg_state}` | Access-permission FSM state (0–5) |
| `HEX1` | `{locked, session_active, done, enter_d}` | System flags |
| `HEX0` | `{cp_active, cp_complete, correct, error}` | Auth/CP result flags |

---

## User Scenarios

### 1. Correct user login
- Type 4-digit password + `D` (terminator)
- **LEDR[1]** pulses once (1 ms — invisible at 1 kHz; debug only)
- **LEDR[3]** turns on, holds ~4 s, then off

### 2. Wrong user login (1st–3rd attempt)
- Type password + `D`
- **LEDR[0]** pulses once (1 ms — debug only)
- **LEDR[2]** blinks 3× at 256 ms intervals, then off

### 3. System lockout (4th wrong attempt)
- **LEDR[2]** blinks 3×
- **LEDR[4]** turns on and stays on
- Keypad input is blocked — further presses have no effect until supervisor unlocks

### 4. Session timeout (5 s idle during entry)
- **LEDR[2]** turns on steady (no blink)
- Stays on until the user presses the first digit of a new attempt
- First digit press resets the timeout counter and clears `Err_LED`

### 5. Supervisor login
- Set `SW[0]` to `1` (supervisor key)
- Type supervisor password + `D`
- **LEDR[3]** holds ~4 s
- **LEDR[9]** turns on (session active)
- **LEDR[8:6]** = `000` — waiting for command

### 6. Supervisor changes user password (`1` → enter)
- **LEDR[8:6]** → `001`
- Type new password + `D` (ENTRY phase)
- Re-type same password + `D` (VERIFY phase)
- If match: **LEDR[3]** holds ~4 s; **LEDR[8:6]** → `000`
- If mismatch: **LEDR[2]** blinks 3×; **LEDR[8:6]** → `000`; supervisor remains in session

### 7. Supervisor changes supervisor password (`4` → enter)
- **LEDR[8:6]** → `010`
- Same ENTRY/VERIFY flow as above

### 8. Supervisor exits session (`2` → enter)
- **LEDR[8:6]** → `011` briefly
- **LEDR[9]** turns off
- System returns to idle

### 9. Supervisor unlocks system (`3` → enter, only when locked)
- **LEDR[8:6]** flashes `100` for 1 cycle (see reliability note)
- **LEDR[4]** turns off (failure counter cleared)
- Supervisor remains in session; **LEDR[9]** stays on

### 10. Wrong password during locked state
- Keypad fully blocked — no LED change, no counter advance
- Only supervisor with `SW[0]=1` can interact

---

## Reliability Notes

### 1. LEDR[0] and LEDR[1] are invisible
`error` and `correct` are 1-cycle pulses at 1 kHz = 1 ms. The human eye cannot see them.
They are useful as debug signals on HEX0 (sampled and held), but as raw LEDs they are misleading.
**Recommendation:** Remove LEDR[0]/LEDR[1] from the user-facing guide; reserve them as internal debug only, or extend them through the `leds.sv` FSM.

### 2. UNLOCK_REQUEST flashes for 1 cycle
`supervisor_requests` auto-clears `UNLOCK_REQUEST` after 1 clock (by design — it is a pulse, not a hold).
LEDR[8:6] will show `100` for 1 ms — invisible. The unlock effect (LEDR[4] turning off) is the visible confirmation.
**Recommendation:** No fix needed; the correct user feedback is LEDR[4] going low, not the sr_state value.

### 3. Timeout clears only on next keypress
After a 5 s timeout, `Err_LED` (LEDR[2]) holds steady until the next digit is pressed.
There is no automatic return to idle appearance — the LED stays on even after the session counter resets.
This is intentional (the user is informed to re-enter), but first-time users may not understand the steady LED.
**Recommendation:** Add a note to the user manual or display a message. No code change needed unless a timer-based auto-clear is desired.

### 4. No entry progress feedback
The user has no visual indication of how many digits have been accepted during password entry.
If the keypad misses a press (mechanical bounce, marginal timing), the user will not know.
**Recommendation:** Implement the HEX digit echo (NEXT_STEPS.md "Ready") — shows each digit on HEX[5:1] as entered.

### 5. Invalid keys (A, B, C, E, F) silently mismatch
Pressing A, B, C, E, or F is treated as a digit mismatch, not a no-op.
Four accidental presses will lock the system.
**Recommendation:** Implement input range validation (NEXT_STEPS.md "Ready") — gate `enter_d` on valid input.

### 6. sr_state encoding requires a reference table
LEDR[8:6] shows a binary number. An operator unfamiliar with the encoding cannot interpret it without the table above.
This is acceptable for a lab demo; for a real deployment, a 7-segment decoder per operation would be clearer.

### 7. No indication of user vs supervisor mode before login
Before the first keypress, all LEDs are off and HEX2 shows state 0.
The user cannot tell whether `SW[0]` is set to supervisor mode without looking at the switch.
**Recommendation:** Could tie LEDR[5] (currently unused) to `key` (SW[0]) as a permanent "supervisor key active" indicator.

---

## What to Add Next (Priority Order)

1. **HEX digit echo** — highest UX value; lets operator verify each digit as typed; shift register in lock_validation_wrapper
2. **Input range validation** — prevents accidental lockout from invalid keys; low effort
3. **LEDR[5] = SW[0] (key indicator)** — zero-effort one-liner in the golden top; tells operator which mode is active
4. **Extend LEDR[0]/LEDR[1] visibility** — either route through leds.sv FSM or remove from LEDR and keep as HEX0 debug only
5. **Supervisor timeout alarm** — blocked on duration/output decisions; see NEXT_STEPS.md
