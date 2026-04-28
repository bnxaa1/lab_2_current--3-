# SystemVerilog Files Overview

This document explains the purpose of each `.sv` file in the project, the design idea behind it, and how the files relate to each other.

---

## High-level design idea

This project implements a digital lock / access-control system for a DE1-SoC FPGA board (Altera Cyclone V). The logic is split into focused modules:

- **Clock division** — scaling 50 MHz to 1 kHz for human-scale timing
- **Input conditioning** — turning a keypad matrix scan into a clean one-cycle pulse
- **Lock validation** — checking whether the entered sequence matches the stored password
- **Access policy** — deciding what the system should do after a correct or incorrect attempt
- **Supervisor session** — handling supervisor commands (unlock, change password, exit)
- **Password change** — atomic two-region write-then-swap for password updates
- **LED output driving** — translating 1-cycle pulse events into visible LED feedback
- **Memory / sequence storage** — RAM with auto-stepping address counter

---

## Files in the active Quartus project

- `lab_2.sv`
- `clock1.sv`
- `keypad_interface.sv`
- `one_pulse_generator.sv`
- `lock_validation.sv`
- `lock_validation_wrapper.sv`
- `codeStorage.sv`
- `access_permission.sv`
- `access_permission_wrapper.sv`
- `supervisor_requests.sv`
- `change_password.sv`
- `leds.sv`

---

## 1) `clock1.sv`

### What it does
Divides the 50 MHz system clock (`clk`) down to a **1 kHz clock** (`clk_out`, period = 1 ms).

### Main logic
Uses a 16-bit counter IP (`sixteenbitsctr`) counting 0 → 49 999, resets on cycle 49 999 (`rst = (q == 16'd49999)`), drives `clk_out = (q < 16'd25000)` — clean 50% duty-cycle 1 kHz output.

### Why this file exists
All FSMs and counters that need human-scale timing (debounce, timeout, lockout) run on `clk1ms` instead of the raw 50 MHz clock. This avoids individually large counter IPs in each module.

### Effects on the design
- `one_pulse_generator`: 4-bit counter at `clk1ms` → 15 cycles × 1 ms = **15 ms debounce**
- `thirteenBitsCtr` timeout: 5 000 cycles × 1 ms = **5 s timeout**

### Relationship to other files
- **instantiated by** `lab_2.sv`
- **uses** `sixteenbitsctr` IP

---

## 2) `keypad_interface.sv`

### What it does
Scans a 4×4 keypad matrix connected to GPIO pins and produces the currently pressed key (`pass[3:0]`) and an active-low enter signal (`Enter`).

### GPIO pin assignment

The keypad's 8 wires are connected to a contiguous block of GPIO_0 header pins:

```
GPIO_0[35:32] → cols[3:0]   (column sense/drive lines)
GPIO_0[31:28] → rows[3:0]   (row sense/drive lines)
```

All 8 lines must have **external pull-up resistors** to VCC so they read high when no key is pressed and when driven as inputs (tri-stated in the SV with `4'bzzzz`).

### Two-phase scanning (7-state FSM)

The scan runs at `clk` (expected `clk1ms`, ~1 kHz):

| State | cols | rows | Action |
|---|---|---|---|
| `S_IDLE` | driven 0 | tri-state | Monitor rows; any row goes low → key detected, go to `S_DEBOUNCE` |
| `S_DEBOUNCE` | driven 0 | tri-state | Wait 15 cycles (≈15 ms); if rows go high again → bounced, back to `S_IDLE` |
| `S_LATCH_ROW` | tri-state | driven 0 | Capture `row_latch = rows`; swap drive direction |
| `S_SETTLE` | tri-state | driven 0 | Wait 2 cycles for GPIO to settle after direction swap |
| `S_LATCH_COL` | tri-state | driven 0 | Capture cols; run `decode_key` → latch `pass`; assert `Enter = 0` |
| `S_PRESSED` | driven 0 | tri-state | Hold `Enter = 0` while key is held; wait for rows to go high (release) |
| `S_REL_DEBOUNCE` | driven 0 | tri-state | Wait 15 cycles for release to settle; deassert `Enter = 1` → back to `S_IDLE` |

**Phase 1 (S_IDLE → S_LATCH_ROW):** All columns are driven low (`cols_oe=1`, `cols=4'b0000`). Rows are tri-stated. When a key is pressed it shorts its row wire to its column wire, pulling that row pin to 0V. This identifies **which row** the pressed key is in.

**Phase 2 (S_LATCH_ROW → S_LATCH_COL):** All rows are now driven low (`rows_oe=1`) and columns are tri-stated. The key short now pulls the column pin to 0V. This identifies **which column** the key is in.

### How `Enter` is generated

`Enter` is active-low and is driven entirely inside the FSM:

1. **`Enter = 1`** in `S_IDLE`, `S_DEBOUNCE`, `S_LATCH_ROW`, `S_SETTLE` (key not yet confirmed).
2. **`Enter = 0`** asserted in `S_LATCH_COL` — exactly when both row and column are known and `pass` is latched. This is the moment a valid key press is confirmed.
3. **`Enter = 0` held** through `S_PRESSED` — the key is physically down.
4. **`Enter = 1`** deasserted at the end of `S_REL_DEBOUNCE` — after 15 cycles of stable release.

`Enter` is therefore a level signal: low for the full duration the key is pressed and stably released. It maps to `enter_al` in `lab_2.sv`, which is then passed to `one_pulse_generator` to produce a single clean `enter_d` pulse for the rest of the design.

### How key values are decoded from pin numbers

**Step 1 — priority encode (active-low one-hot → 2-bit binary):**

```sv
function automatic [1:0] encode4 (input [3:0] al_onehot);
    casez (~al_onehot)
        4'b???1 : encode4 = 2'd0;   // bit 0 pulled low
        4'b??10 : encode4 = 2'd1;   // bit 1 pulled low
        4'b?100 : encode4 = 2'd2;   // bit 2 pulled low
        4'b1000 : encode4 = 2'd3;   // bit 3 pulled low
    endcase
endfunction
```

This converts which GPIO line went low into a 2-bit index. `encode4(row_latch)` gives a 2-bit row index; `encode4(cols)` gives a 2-bit column index.

**Step 2 — decode_key lookup table ({row, col} → hex digit):**

```sv
case ({r, c})   // r=encode4(row), c=encode4(col)
    4'hF: 4'h1    4'hE: 4'h2    4'hD: 4'h3    4'hC: 4'hA
    4'hB: 4'h4    4'hA: 4'h5    4'h9: 4'h6    4'h8: 4'hB
    4'h7: 4'h7    4'h6: 4'h8    4'h5: 4'h9    4'h4: 4'hC
    4'h3: 4'hE    4'h2: 4'h0    4'h1: 4'hF    4'h0: 4'hD
endcase
```

**Why the indexing appears reversed:** The physical keypad top row (containing `1 2 3 A`) connects to `GPIO_0[31:28]` as `rows[3:0]`, with the top row on `GPIO_0[31]` = `rows[3]`. `encode4` returns 3 for this row. Similarly, the left column (containing `1 4 7 E`) connects to `GPIO_0[35]` = `cols[3]`, which encodes to 3. The decode_key table maps `{r=3, c=3}` = `4'hF` → `4'h1`, correctly giving key `1` for the top-left position.

The full mapping from physical position to GPIO to decoded value:

| Physical key | Physical position | Active GPIO line | encode4 result | decode_key output |
|---|---|---|---|---|
| `1` | Row 1, Col 1 | rows[3]=GPIO_0[31], cols[3]=GPIO_0[35] | r=3, c=3 | `4'h1` |
| `D` *(terminator)* | Row 4, Col 4 | rows[0]=GPIO_0[28], cols[0]=GPIO_0[32] | r=0, c=0 | `4'hD` |
| `0` | Row 4, Col 2 | rows[0]=GPIO_0[28], cols[2]=GPIO_0[34] | r=0, c=2 | `4'h0` |
| `5` | Row 2, Col 2 | rows[2]=GPIO_0[30], cols[2]=GPIO_0[34] | r=2, c=2 | `4'h5` |

**Terminator key `D`:** bottom-right of the keypad → `rows[0]` & `cols[0]` both go low → `encode4` gives r=0, c=0 → `decode_key(4'h0)` = `4'hD`. This is the key the user presses to confirm their password entry.

### Why this file exists
Decouples the physical keypad scanning from all higher-level logic. The rest of the design sees `switches` + `enter_al` — identical interface to the forced-signal testbench approach (`force uut.switches / uut.enter_al`).

### Relationship to other files
- **instantiated by** `lab_2.sv`
- drives `switches` (`pass`) and `enter_al` (`Enter`) into `access_permission_wrapper` and `one_pulse_generator`

---

## 3) `one_pulse_generator.sv`

### What it does
Generates a debounced one-pulse signal (`enter_d`) from the active-low enter button (`enter_al`).

### Main logic
5-state FSM + 4-bit counter. Debounce window = 15 `clk1ms` cycles = **15 ms**. Produces exactly one `enter_d` pulse per valid press regardless of button bounce.

### Why this file exists
Button handling (debounce, one-pulse generation) is separate from password checking logic. The same pulse generator is reused anywhere clean enter detection is needed.

### Relationship to other files
- **uses** `counter` IP
- **instantiated by** `lock_validation.sv`

---

## 4) `lock_validation.sv`

### What it does
FSM that decides whether the entered digit sequence is correct or incorrect by comparing each digit against the stored password from RAM.

### Main logic
4-state FSM:
- **S0** — still correct so far; advance on each matching digit
- **S1** — success state; asserts `correct`
- **S2** — a mismatch or incomplete entry; waits for the attempt to finish
- **S3** — failure state; asserts `error`

Internally instantiates `one_pulse_generator` to produce the clean `enter_d` pulse.

Terminator key: `4'hD` (bottom-right keypad key). When `switches == 4'hD`, the FSM checks whether all digits matched and transitions to S1 (success) or S3 (failure).

### Why this file exists
All password-checking rules are in one place. `lock_validation` answers: **was the entry right or wrong?** `access_permission` answers: **what should the system do next?**

### Relationship to other files
- **instantiated by** `lock_validation_wrapper.sv`
- **instantiates** `one_pulse_generator.sv`
- drives `correct`, `error`, `enter_d_raw` up to the wrapper

---

## 5) `lock_validation_wrapper.sv`

### What it does
Wraps `lock_validation` and `codeStorage` together, and applies security gating: blocks entry while locked and no supervisor key is present.

### Main logic
- `enter_d = enter_d_raw && (!locked || key)` — gate: blocked when `locked && !key`
- `lock_validation.srst = rst_lv | (locked && !key) | cp_srst_lv` — holds FSM in S0 when locked without supervisor key, or during change_password ENTRY
- `rst_codeNum = rst_lv || !resetN || cp_ctrRst` — synchronous reset for codeStorage counter
- Exposes `done` (codeStorage counter at 9) and the gated `enter_d` upward

### Why this file exists
Keeps the security gating (locked-state blocking) and the RAM address reset logic separate from `lock_validation`'s digit-comparison FSM.

### Relationship to other files
- **instantiated by** `access_permission_wrapper.sv`
- **instantiates** `lock_validation.sv` and `codeStorage.sv`

---

## 6) `codeStorage.sv`

### What it does
Provides a RAM access wrapper with automatic address stepping: `rdaddress = rStartingAddress + ctr`, `wraddress = wStartingAddress + ctr`.

### Main logic
Combines a `ram` instance (64×4 bit, behavioral simulation model `ram_sim.v`) with a `counter` instance for address progression. The counter advances once per debounced `enter_d` pulse (`clk_en = enter_d`). `done` fires when `ctr == 9` (max sequence length).

End-of-code marker stored in RAM: `4'hD` (= `4'b1101` = 13).

### Why this file exists
Simplifies sequential reading/writing of multi-digit code sequences. The starting address selects which RAM region to read (user A, user B, supervisor A, supervisor B).

### Relationship to other files
- **uses** `ram_sim.v` (behavioral model for simulation) / `ram.v` (synthesis)
- **uses** `counter` IP
- **instantiated by** `lock_validation_wrapper.sv`

---

## 7) `access_permission.sv`

### What it does
Control FSM for the overall access flow — user authentication, supervisor authentication, session management, and output control.

### Main logic
7-state FSM (S4 unused after S3/S4 merge):

| State | Role |
|---|---|
| S0 | Idle — wait for first digit press |
| S1 | User authentication in progress |
| S2 | Supervisor authentication in progress |
| S3 | Supervisor session (handles both locked and unlocked via `input_cond[2]`) |
| S5 | Error — assert `Err_LED` for 1 cycle → S0 |
| S6 | Correct — assert `Corr_LED` for 1 cycle → S0 |

Key behaviors:
- S0→S1: first user digit press (`key=0, locked=0, enter=1`)
- S0→S2: supervisor key present + first digit (`key=1, enter=1`)
- S1: `key=1` → abort to S0; `timeOut` → abort to S0; `correct` → S6; `error` → S5, increment failure counter
- S2: `key=0` → abort to S0; `correct` → S3; `error` → S5
- S3: exit via `srst_access` (driven by `exit_req` from `supervisor_requests`); unlock via `unlock_req`

### Relationship to other files
- **instantiated by** `access_permission_wrapper.sv`
- drives `rst_lv`, `increment`, `rst_timeoutCtr`, `session_active`, `state_p` upward

---

## 8) `access_permission_wrapper.sv`

### What it does
Provides the support logic around `access_permission`: timeout counter, failure counter, address mux for RAM region selection, and the `lock_validation_wrapper` instance.

### Main logic
- **Timeout counter:** `thirteenBitsCtr` (13-bit LPM); fires at 5 000 `clk1ms` cycles = 5 s
- **Failure counter:** `ThreeBitsCounter` (3-bit LPM); `locked = (ctr == 4)`. Reset by `unlock_req | ap_rst_failureCtr | rst_failureCtr`. Port renamed `clk_en → cnt_en` so `sclr` always fires regardless of `increment`.
- **Address mux:** `rStartingAddress = cp_active ? target_addr : {key, active_bit, 4'b0000}`; `active_bit` is `user_active` or `super_active` (flipped on `cp_complete`)
- **Address swap registers:** `user_active`, `super_active` — no `resetN` reset (survive restart), only flip on `cp_complete`
- `effective_rst_lv = rst_lv | srst_access` ensures `srst_access` resets all submodules

### Relationship to other files
- **instantiated by** `lab_2.sv`
- **instantiates** `access_permission.sv`, `lock_validation_wrapper.sv`, `thirteenBitsCtr`, `ThreeBitsCounter`

---

## 9) `supervisor_requests.sv`

### What it does
A menu-reader FSM that decodes the supervisor's single-digit keypad command during a supervisor session (S3).

### Main logic
Waits for `session_active = 1`, then on the next `enter_d` pulse decodes `switches`:

| `switches` | Output asserted | Command |
|---|---|---|
| `4'b0001` | `change_user_req` | Change user password |
| `4'b0010` | `exit_req` | Exit supervisor session → S0 |
| `4'b0011` | `unlock_req` | Clear failure counter |
| `4'b0100` | `change_super_req` | Change supervisor password |

Holds the output until `cp_done` fires (change complete or failed) or `exit_req` resets the session.

### Why this file exists
Keeps supervisor command decoding outside `access_permission.sv`, which stays focused on FSM transitions and policy.

### Relationship to other files
- **instantiated by** `lab_2.sv`
- drives `exit_req` → `srst_access` in `lab_2.sv`; `unlock_req`, `change_user_req`, `change_super_req` directly

---

## 10) `change_password.sv`

### What it does
Manages the full password-change flow: write new password to inactive RAM region, verify by re-entry, then signal the wrapper to atomically swap the active region pointer.

### Main logic
5-state FSM: `IDLE → ENTRY → VERIFY → DONE / ERROR`

- **IDLE:** waits for `start`. On `start` (Mealy): resets counter and `lock_validation`, goes to ENTRY.
- **ENTRY:** `cp_active=1`, `srst_lv=1`, `wren=1`; writes `switches` to inactive region on each `enter_d`. Exits to VERIFY on `switches==4'hD` or `done`.
- **VERIFY:** `cp_active=1`; `lock_validation` compares re-entered digits against the inactive region. Exits to DONE on `lv_correct`, ERROR on `lv_error`.
- **DONE:** asserts `cp_complete` for 1 cycle → wrapper flips active pointer → IDLE.
- **ERROR:** asserts `cp_fail` for 1 cycle → supervisor session preserved → IDLE.

`target_addr = active_addr ^ 6'b010000` — computed inside the module.

### Why this file exists
Isolates the multi-phase write-verify-swap sequence from the supervisor session logic. `supervisor_requests` only needs to signal which password to change; `change_password` handles all timing.

### Relationship to other files
- **instantiated by** `lab_2.sv`
- drives `cp_active`, `wren`, `dataIn`, `target_addr`, `ctrRst`, `srst_lv`, `cp_complete`, `cp_fail` into `lab_2.sv` and `access_permission_wrapper.sv`

---

## 11) `leds.sv`

### What it does
Translates 1-cycle pulse events from `access_permission` and other modules into human-visible LED output patterns.

### Main logic
6-state FSM driven by `twelveBitsCounter` IP (12-bit, 1 kHz):

| State | LED output | Duration | Transition |
|---|---|---|---|
| IDLE | all off | — | on `corr_in` → CORR_HOLD; on `err_in` → BLINK_ON; on `timeout_in` → TIMEOUT_ON |
| CORR_HOLD | `Corr_LED=1` | 3 000 cycles (3 s) | → IDLE |
| BLINK_ON | `Err_LED=1` | 250 cycles (250 ms) | → BLINK_OFF |
| BLINK_OFF | `Err_LED=0` | 250 cycles (250 ms) | if 3 blinks done → IDLE; else → BLINK_ON |
| TIMEOUT_ON | `Err_LED=1` | 512 cycles (ctr[9]) | → TIMEOUT_OFF |
| TIMEOUT_OFF | `Err_LED=0` | 512 cycles (ctr[9]) | → IDLE |

Additional output: `Lock_LED = locked_in` — purely combinational, always reflects lockout state.

`corr_in` sources (OR'd in `lab_2.sv`): user auth success (`ap_corr_pulse`), supervisor auth success (`sup_corr_pulse`), password change verified (`cp_complete`), system unlocked (`unlock_req`).

### Relationship to other files
- **uses** `twelveBitsCounter` IP (12-bit LPM counter)
- **instantiated by** `lab_2.sv`
- inputs: `corr_in`, `err_in`, `timeout_in`, `locked_in`; outputs: `Corr_LED`, `Err_LED`, `Lock_LED`

---

## 12) `lab_2.sv` (top-level)

### What it does
Top-level integration module. Connects all submodules, clock divider, and keypad interface.

### Main logic
Wiring only — no FSM states. Key connections:
- `clock1` → `clk1ms` used by all submodules
- `keypad_interface` → `switches`, `enter_al`
- `access_permission_wrapper` → `correct`, `error`, `locked`, `timeOut`, `session_active`, `enter_d`, `done`, `active_addr`, all reset/control signals
- `supervisor_requests` → `exit_req`, `unlock_req`, `change_user_req`, `change_super_req`; `exit_req` OR'd with external `srst_access` before feeding to wrapper
- `change_password` → `cp_active`, `cp_wren`, `dataIn_cp`, `target_addr`, `cp_ctrRst`, `cp_srst_lv`, `cp_complete`, `cp_fail`
- `leds` → `Corr_LED`, `Err_LED`, `Lock_LED`; `corr_in = ap_corr_pulse | sup_corr_pulse | cp_complete | unlock_req`
- `sup_corr_pulse` edge detector: 1-cycle pulse on rising edge of `session_active`

### Relationship to other files
- **instantiates** all modules above
- is the active **top-level entity** in `lab_2.qsf`
- mapped to DE1-SoC pins via `DE1_SoC_golden_top.v`

---

## Design relationships summary

```
50 MHz clk
    └── clock1.sv → clk1ms (1 kHz)
                        │
                ┌───────┴────────┐
        keypad_interface      access_permission_wrapper
           (cols/rows)            │
               │          ┌──────┴────────────────────────┐
         switches +    thirteenBitsCtr  ThreeBitsCounter  lock_validation_wrapper
         enter_al          (timeout)      (failures)         │
                │                                   ┌────────┴────────────┐
                └───────────────────────────  codeStorage      lock_validation
                                              (RAM+ctr)          (digit check)
                                                                      │
                                                              one_pulse_generator
                                                                (debounce)
supervisor_requests ──── change_password
        │                      │
      exit_req           cp_active/wren/dataIn/...
        │
    srst_access → access_permission (FSM S0–S6)
                        │
                      leds.sv → Corr_LED / Err_LED / Lock_LED
```

---

## Why this overall structure makes sense

The project is organized around **functional responsibility**:

- **top-level wiring** → `lab_2.sv`
- **clock division** → `clock1.sv`
- **keypad scanning** → `keypad_interface.sv`
- **signal conditioning** → `one_pulse_generator.sv`
- **verification logic** → `lock_validation.sv`
- **RAM + address stepping** → `codeStorage.sv`
- **lock gating + submodule wiring** → `lock_validation_wrapper.sv`
- **access wrapper / timer / failure counter** → `access_permission_wrapper.sv`
- **system reaction / policy FSM** → `access_permission.sv`
- **supervisor command decoding** → `supervisor_requests.sv`
- **password change flow** → `change_password.sv`
- **LED output driving** → `leds.sv`
