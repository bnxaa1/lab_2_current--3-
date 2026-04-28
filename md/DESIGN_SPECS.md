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

After the 3rd blink the LED goes off and `leds.sv` returns to IDLE.

**Rationale:** 3 blinks is the standard "access denied" pattern on physical locks — unambiguous and impossible to miss. The 250 ms cadence is the minimum reliably visible to a human eye.

### 1.2 Correct LED — static hold on correct

**Trigger:** `corr_in` pulse to `leds.sv`; asserted by `access_permission` (S6 → 1-cycle `ap_corr_pulse`), rising edge of `session_active` (supervisor auth success), `cp_complete` (password change verified), or `unlock_req` (supervisor unlocks locked system).

**Behavior:** Latch any `corr_in` pulse, drive the LED **static ON** for a fixed hold duration, then off:

| Parameter | Value |
|---|---|
| Hold duration | **3 000 ms** (3 s at `clk1ms`) |

After 3 s the LED goes off and `leds.sv` returns to IDLE.

**Rationale:** Static on (not blinking) distinguishes the correct case from the error blink pattern. 3 s is long enough to be clearly visible.

### 1.3 Timeout LED — slow blink

**Trigger:** `timeout_in` input to `leds.sv`; driven by `timeOut` (wire-level, stays high for 1 `clk1ms` cycle then resets).

**Behavior:** `Err_LED` enters a slow blink pattern while timeout is signalled:

| Phase | Duration |
|---|---|
| `TIMEOUT_ON` | 512 `clk1ms` cycles (~512 ms) |
| `TIMEOUT_OFF` | 512 `clk1ms` cycles (~512 ms) |

`leds.sv` uses `ctr[9]` (bit 9 of the 12-bit `twelveBitsCounter`) for the 512-cycle threshold.

After one `TIMEOUT_ON / TIMEOUT_OFF` cycle the FSM returns to IDLE.

### 1.4 Lock LED — static level

**Trigger:** `locked_in` input to `leds.sv`; driven by `locked` from `access_permission_wrapper`.

**Behavior:** `Lock_LED = locked_in` — purely combinational, no FSM involvement. Reflects lock state instantly.

### 1.5 `leds.sv` FSM

**Counter:** `twelveBitsCounter` IP (12-bit LPM counter, existing IP file).

```
IDLE        — wait for corr_in or err_in or timeout_in
CORR_HOLD   — Corr_LED=1; count 3 000 cycles → IDLE
BLINK_ON    — Err_LED=1;  count 250 cycles  → BLINK_OFF
BLINK_OFF   — Err_LED=0;  count 250 cycles
              if blink_cnt < 3 → BLINK_ON
              else → IDLE
TIMEOUT_ON  — Err_LED=1;  ctr[9]=1 → TIMEOUT_OFF
TIMEOUT_OFF — Err_LED=0;  ctr[9]=1 → IDLE
```

Priority: `corr_in` > `err_in` > `timeout_in` in IDLE (first seen wins; events are mutually exclusive during normal use).

---

## 2. Supervisor Session — Command Selection

### 2.1 Mechanism

Commands are entered via the existing keypad after the supervisor reaches S3.

**Protocol:** One digit press + enter = one command. No end-marker required.

| Supervisor presses | `switches` | Command | Available in |
|---|---|---|---|
| `1` + enter | `4'b0001` | Change user password | S3 only |
| `2` + enter | `4'b0010` | Exit (return to S0) | S3 |
| `3` + enter | `4'b0011` | Unlock system | S3 (when `locked`) |
| `4` + enter | `4'b0100` | Change supervisor password | S3 only |

**Rationale:** Single-digit selection reuses existing `enter_d` pulse routing with no new hardware. Multi-digit command sequences would add complexity with no benefit given only 4 commands exist.

### 2.2 `supervisor_requests.sv` role

`supervisor_requests` is a menu-reader FSM:

1. Enters active mode when `session_active = 1` (AP FSM in S3).
2. Waits for the next `enter_d` pulse.
3. Decodes `switches` into one of four individual 1-bit outputs: `exit_req`, `unlock_req`, `change_user_req`, `change_super_req`.
4. Holds the active command until `cp_done` fires (change complete or failed) or `exit_req` resets via `srst_access`.

`exit_req` is OR'd with the external `srst_access` in `lab_2.sv`, resetting the AP FSM, `lock_validation`, `codeStorage` counter, and timeout counter in one signal.

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
| Successful auth | Alarm clears if supervisor correctly authenticates after it fires |
| `resetN` only | Most strict; forces a physical board reset |

**Recommendation:** Key removal clears the alarm.

### 3.6 Wrong supervisor password — PENDING DECISION

Does entering a wrong supervisor password in S2 trigger the alarm **immediately**, or does only the timeout trigger it?

**Decision needed.**

### 3.7 Implementation notes

- Separate counter from the user timeout counter (`thirteenBitsCtr`).
- Resets to 0 on S0→S2 (key-in trigger), mirroring how `rst_timeoutCtr` fires on S0→S1.
- Alarm output should **latch** — stays asserted until the clear condition is met.

---

## 4. Memory Map

| Region | addr[5:4] | Addresses | `rStartingAddress` |
|---|---|---|---|
| User A (default active) | `2'b00` | 0–15 | `6'b000000` |
| User B (swap target) | `2'b01` | 16–31 | `6'b010000` |
| Supervisor A (default active) | `2'b10` | 32–47 | `6'b100000` |
| Supervisor B (swap target) | `2'b11` | 48–63 | `6'b110000` |

Default password contents (from `ramm.mif`):

| Region | Addresses | Contents |
|---|---|---|
| User A | 0–4 | `1, 2, 3, 4, 13` (D terminator at addr 4) |
| Supervisor A | 32–36 | `2, 0, 2, 6, 13` (D terminator at addr 36) |

End-of-code marker: `4'hD = 4'b1101 = 13`. Digit `D` is the bottom-right key on the 4×4 keypad.

Address derivation in `access_permission_wrapper.sv`:
```sv
assign normal_rAddr = {key, key ? super_active : user_active, 4'b0000};
```
- Bit 5 = `key` (user vs supervisor)
- Bit 4 = `user_active` or `super_active` (region A vs B, flipped on `cp_complete`)
- Bits 3:0 = `0000` (counter adds offset within region)

---

## 5. Pending Decisions Summary

| # | Topic | Options | Blocking |
|---|---|---|---|
| A | Supervisor alarm duration | 10 s / **15 s** / 30 s | `access_permission_wrapper.sv` counter IP size |
| B | Alarm output type | Dedicated port / shared `Err_LED` | Top-level port list, `leds.sv` |
| C | Alarm clear condition | Key removal / successful auth / `resetN` | `access_permission.sv` alarm latch logic |
| D | Wrong supervisor password → immediate alarm? | Yes / No | `access_permission.sv` S5 path |
