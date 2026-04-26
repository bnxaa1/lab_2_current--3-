# Design Specifications

This document records all confirmed design decisions and open questions for the system.
It is the authoritative reference before any implementation begins on a feature.

---

## 1. LED Behavior

### 1.1 Error LED — 3 blinks on error

**Trigger:** `Err_LED` 1-cycle pulse from `access_permission` (asserted in S5).

**Behavior:** Latch the pulse in `leds.sv`, then drive 3 visible blink cycles:

| Phase | Duration |
|---|---|
| Blink ON | 250 ms (250 `clk1ms` cycles) |
| Blink OFF | 250 ms (250 `clk1ms` cycles) |
| Full sequence | 3 × 500 ms = **1 500 ms total** |

After the 3rd blink the LED goes off and `leds.sv` returns to idle.

**Rationale:** 3 blinks is the standard "access denied" pattern on physical locks — unambiguous and impossible to miss. The 250 ms cadence is the minimum reliably visible to a human eye.

### 1.2 Correct LED — static hold on correct

**Trigger:** `Corr_LED` 1-cycle pulse from `access_permission` (asserted in S6).

**Behavior:** Latch the pulse, drive the LED **static ON** for a fixed hold duration, then off:

| Parameter | Value |
|---|---|
| Hold duration | **3 000 ms** (3 s at `clk1ms`) |

After 3 s the LED goes off and `leds.sv` returns to idle.

**Rationale:** S6 is a 1-cycle state — the raw `Corr_LED` is only 1 ms wide. Latching and holding for 3 s gives the user clear visual confirmation that access was granted. Static on (not blinking) distinguishes the correct case from the error pattern.

### 1.3 Counter requirement in `leds.sv`

The existing `clk_slow` generator uses a **4-bit counter IP** (`lpm_width = 4`) giving a 14 ms period — invisible to the human eye and useless for 250 ms blink timing.

**Required change:** Replace the 4-bit counter with a timing mechanism capable of counting **250 cycles** (250 ms) at `clk1ms`. Options:

| Option | Detail |
|---|---|
| **FSM + cycle counter** (recommended) | Add a 12-bit cycle counter inside `leds.sv` driven by `clk1ms`; count to 249 for each half-blink. No new IP needed. |
| Wider LPM counter IP | Generate a new `lpm_counter` with `lpm_width = 9` (counts 0–499); period = 500 cycles = 500 ms per blink ON+OFF. |

The FSM approach is preferred — it avoids an extra IP and keeps the timing logic explicit and readable.

### 1.4 `leds.sv` FSM sketch

```
IDLE       — wait for Corr_LED or Err_LED pulse
BLINK_ON   — drive err_led_out=1; count 250 cycles → BLINK_OFF
BLINK_OFF  — drive err_led_out=0; count 250 cycles
              if blink_count < 3 → BLINK_ON
              else → IDLE
CORR_HOLD  — drive corr_led_out=1; count 3 000 cycles → IDLE
```

Both paths are mutually exclusive (system cannot produce `correct` and `error` simultaneously).

---

## 2. Supervisor Session — Command Selection

### 2.1 Mechanism

No UART or Nios-V decoder will be implemented. Commands are entered via the existing keypad after the supervisor reaches S3 or S4.

**Protocol:** One digit press + enter = one command. No end-marker required.

| Supervisor presses | `switches` | Command | Available in |
|---|---|---|---|
| `1` + enter | `4'b0001` | Change user password | S3 only |
| `2` + enter | `4'b0010` | Exit (return to S0) | S3, S4 |
| `3` + enter | `4'b0011` | Unlock system | S4 only |
| `4` + enter | `4'b0100` | Change supervisor password | S3 only |

**Rationale:** Single-digit selection reuses existing `enter_d` pulse routing with no new hardware. Multi-digit command sequences would add complexity with no benefit given only 4 commands exist.

### 2.2 `supervisor_requests.sv` role

`supervisor_requests` acts as a one-deep "menu reader" FSM:

1. Enters active mode when `access_state` = S3 or S4.
2. Waits for the next `enter_d` pulse.
3. Latches `switches` as `cmd_request[2:0]`.
4. Holds that value until the session ends (EXIT or reset).

`lock_validation` must be held in reset during S3/S4 — it is irrelevant for command selection and must not interpret the single digit press as a password digit.

### 2.3 `access_permission.sv` changes needed

- Add `input logic [2:0] cmd_request` port.
- S3 transitions:
  - `cmd_request == 3'd2` (EXIT) → assert `rst_lv`, go to S0.
  - `cmd_request == 3'd1` (CHANGE_USER_PASS) → stay in S3; signal `change_password` module to start.
  - `cmd_request == 3'd4` (CHANGE_SUPER_PASS) → stay in S3; signal `change_password` module (different target region).
- S4 transitions:
  - `cmd_request == 3'd2` (EXIT) → assert `rst_lv`, go to S0.
  - `cmd_request == 3'd3` (UNLOCK) → assert `rst_failureCtr`, go to S0.

---

## 3. Supervisor Authentication Timeout and Alarm

### 3.1 What it protects against

If someone steals or finds the supervisor key and inserts it into the lock, they have limited time to enter the supervisor password before an alarm fires. The supervisor path currently has no timeout (S2 waits forever).

### 3.2 Trigger condition

Alarm fires when:
- Key is inserted (`key=1`), FSM is in S2, AND
- The supervisor does **not** complete authentication within the alarm window.

### 3.3 Alarm duration — PENDING DECISION

| Option | Value | Notes |
|---|---|---|
| Strict | 10 s (10 000 `clk1ms` cycles) | Tight; may frustrate a legitimate slow supervisor |
| **Recommended** | 15 s (15 000 cycles) | Comfortable margin; bad actor can't try more than ~1 attempt quietly |
| Lenient | 30 s (30 000 cycles) | Enough time for ~2 slow attempts before alarm |

**Decision needed:** confirm 10 s, 15 s, or 30 s.

A 14-bit counter is required for 15 000 cycles (`2^14 = 16 384 > 15 000`); a 15-bit counter for 30 000 cycles.

### 3.4 Alarm output — PENDING DECISION

| Option | Detail |
|---|---|
| Dedicated `alarm` top-level output | Cleanest; wired to a buzzer or separate FPGA LED |
| Shared with `Err_LED` | Simpler; reuses existing LED hardware |

**Decision needed:** dedicated port or shared LED?

### 3.5 Alarm clear condition — PENDING DECISION (recommendation below)

| Option | Behavior |
|---|---|
| **Key removal (recommended)** | Alarm clears when `key` goes low; models the physical resolution |
| Successful auth | Alarm clears if supervisor correctly authenticates after it fires (key holder is legitimate) |
| `resetN` only | Most strict; forces a physical board reset |

**Recommendation:** Key removal clears the alarm. This matches the physical model — the threat ends when the key is removed. If the recommendation is accepted, no extra latch-clear logic is needed beyond watching `key`.

### 3.6 Wrong supervisor password — PENDING DECISION

Does entering a wrong supervisor password in S2 trigger the alarm **immediately** (in addition to returning to S0 via S5), or does only the timeout trigger it?

- **Immediate alarm on wrong password:** stronger security signal; any unauthorized attempt flags itself at once.
- **Timeout only:** wrong password just resets to S0; alarm only fires on prolonged inactivity.

**Decision needed.**

### 3.7 Implementation notes

- The supervisor alarm counter must be a **separate counter** from the user timeout counter (`thirteenBitsCtr`). The two can run concurrently (user timeout timer and supervisor alarm timer are independent events on different FSM paths).
- The alarm counter resets to 0 on S0→S2 (key-in trigger), exactly mirroring how `rst_timeoutCtr` fires on S0→S1.
- The alarm output should **latch** (not go low on its own) — it stays asserted until the clear condition is met.

---

## 4. Memory Map (reference)

| Region | Addresses | `rStartingAddress` | Contents |
|---|---|---|---|
| User password | 0 – 9 | `5'b00000` | `1, 2, 3, 4, 10` at addr 0–4 |
| Supervisor password | 10 – 19 | `5'b01010` | (not used in current RAM layout) |
| Supervisor password (active) | 20 – 24 | `5'b10100` | `2, 0, 2, 6, 10` |
| Temp / change-password staging | 20 – 29 | `5'b10100` | Repurposed for `change_password.sv` |

---

## 5. Pending Decisions Summary

| # | Topic | Options | Blocking |
|---|---|---|---|
| A | Supervisor alarm duration | 10 s / **15 s** / 30 s | `access_permission_wrapper.sv` counter IP size |
| B | Alarm output type | Dedicated port / shared `Err_LED` | Top-level port list, `leds.sv` |
| C | Alarm clear condition | Key removal / successful auth / `resetN` | `access_permission.sv` alarm latch logic |
| D | Wrong supervisor password → immediate alarm? | Yes / No | `access_permission.sv` S5 path |
