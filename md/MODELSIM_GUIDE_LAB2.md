# ModelSim Testbench — Full System (lab_2) Guide

Testbench: `tb_lab_2.sv`  
DUT: `lab_2.sv` (all modules integrated)  
Script: `sim_lab2.do`  
Altera install: `C:\altera_lite\25.1std\`

---

## Overview

Two phases:

1. **Library setup** (once only — skip if already done for `sim_apw.do` or `sim.do`)
2. **Compile & simulate** (every time source files change)

`sim_lab2.do` automates Phase 2 completely.

### How the testbench drives the DUT

`lab_2` now takes `cols`/`rows` inout ports from `keypad_interface` instead of raw
`switches`/`enter_al`. The testbench **bypasses the GPIO matrix** by using `force` to drive
the internal wires `uut.switches` and `uut.enter_al` directly.  
This drives the same nets consumed by `one_pulse_generator` → `lock_validation` →
`access_permission_wrapper` unchanged, while keeping `keypad_interface` idle.  
Weak pull-ups on `cols`/`rows` keep the `keypad_interface` FSM in `S_IDLE` throughout.

---

## Phase 1 — Compile Altera Simulation Libraries (once only)

> Skip this phase entirely if the libraries already exist from a previous run of `sim.do` or `sim_apw.do`.

### Step 1 — Open ModelSim and set working directory

```tcl
cd {C:/Users/mahaz/Desktop/lab_2_current (3)}
```

### Step 2 — Create the work library

```tcl
vlib work
vmap work work
```

### Step 3 — `lpm_ver` (counter IPs)

```tcl
vlib lpm_ver
vmap lpm_ver lpm_ver
vlog -work lpm_ver {C:/altera_lite/25.1std/quartus/eda/sim_lib/220model.v}
```

### Step 4 — `altera_mf_ver` (altsyncram — RAM IP)

```tcl
vlib altera_mf_ver
vmap altera_mf_ver altera_mf_ver
vlog -work altera_mf_ver {C:/altera_lite/25.1std/quartus/eda/sim_lib/altera_mf.v}
```

### Step 5 — `altera_ver`

```tcl
vlib altera_ver
vmap altera_ver altera_ver
vlog -work altera_ver {C:/altera_lite/25.1std/quartus/eda/sim_lib/altera_primitives.v}
```

### Step 6 — `sgate_ver`

```tcl
vlib sgate_ver
vmap sgate_ver sgate_ver
vlog -work sgate_ver {C:/altera_lite/25.1std/quartus/eda/sim_lib/sgate.v}
```

### Step 7 — `altera_lnsim_ver` (Cyclone V models)

```tcl
vlib altera_lnsim_ver
vmap altera_lnsim_ver altera_lnsim_ver
vlog -sv -work altera_lnsim_ver {C:/altera_lite/25.1std/quartus/eda/sim_lib/altera_lnsim.sv}
```

> Libraries are saved to disk. Phase 1 never needs to be repeated unless Quartus is reinstalled or the project folder moves.

---

## Phase 2 — Compile Design Files and Run Simulation

### Step 8 — Compile Altera IP files (Verilog)

```tcl
vlog -work work counter.v
vlog -work work sixteenbitsctr.v
vlog -work work thirteenBitsCtr.v
vlog -work work ThreeBitsCounter.v
vlog -work work ram.v
```

### Step 9 — Compile design files (SystemVerilog, dependency order)

```tcl
vlog -sv -work work clock1.sv
vlog -sv -work work keypad_interface.sv
vlog -sv -work work one_pulse_generator.sv
vlog -sv -work work codeStorage.sv
vlog -sv -work work lock_validation.sv
vlog -sv -work work lock_validation_wrapper.sv
vlog -sv -work work access_permission.sv
vlog -sv -work work access_permission_wrapper.sv
vlog -sv -work work supervisor_requests.sv
vlog -sv -work work change_password.sv
vlog -sv -work work leds.sv
vlog -sv -work work lab_2.sv
```

### Step 10 — Compile testbench

```tcl
vlog -sv -work work tb_lab_2.sv
```

### Step 11 — Launch simulation

```tcl
vsim -t 1ns \
     -L lpm_ver \
     -L altera_mf_ver \
     -L altera_ver \
     -L sgate_ver \
     -L altera_lnsim_ver \
     work.tb_lab_2
```

### Step 12 — Add waveforms

```tcl
add wave -divider "TB Control"
add wave /tb_lab_2/clk
add wave /tb_lab_2/resetN
add wave /tb_lab_2/srst_access
add wave /tb_lab_2/key

add wave -divider "Keypad (forced)"
add wave /tb_lab_2/uut/switches
add wave /tb_lab_2/uut/enter_al

add wave -divider "Outputs"
add wave /tb_lab_2/correct
add wave /tb_lab_2/error
add wave /tb_lab_2/Corr_LED
add wave /tb_lab_2/Err_LED

add wave -divider "AP FSM"
add wave /tb_lab_2/uut/access_state_p
add wave /tb_lab_2/uut/apw1/ap1/state_reg
add wave /tb_lab_2/uut/session_active
add wave /tb_lab_2/uut/locked

add wave -divider "lock_validation"
add wave /tb_lab_2/uut/apw1/lvw1/u_lock_validation/state_reg
add wave /tb_lab_2/uut/enter_d
add wave /tb_lab_2/uut/done
add wave /tb_lab_2/uut/apw1/lvw1/code
add wave /tb_lab_2/uut/apw1/rStartingAddress

add wave -divider "Failure / Timeout counters"
add wave /tb_lab_2/uut/apw1/threeBitsCounter
add wave /tb_lab_2/uut/apw1/ThirteenBitsCounter
add wave /tb_lab_2/uut/timeOut

add wave -divider "supervisor_requests"
add wave /tb_lab_2/uut/sr1/state_reg
add wave /tb_lab_2/uut/exit_req
add wave /tb_lab_2/uut/unlock_req
add wave /tb_lab_2/uut/change_user_req
add wave /tb_lab_2/uut/change_super_req

add wave -divider "change_password"
add wave /tb_lab_2/uut/cp1/state_reg
add wave /tb_lab_2/uut/cp_active
add wave /tb_lab_2/uut/cp_complete
add wave /tb_lab_2/uut/cp_fail
add wave /tb_lab_2/uut/target_addr
add wave /tb_lab_2/uut/active_addr
add wave /tb_lab_2/uut/cp_wren
add wave /tb_lab_2/uut/dataIn_cp

add wave -divider "Address swap registers"
add wave /tb_lab_2/uut/apw1/user_active
add wave /tb_lab_2/uut/apw1/super_active
```

### Step 13 — Run simulation

```tcl
run -all
```

The transcript prints `PASS`/`FAIL` for every check across all 13 tests.  
Press **F4** to open the waveform viewer.

---

## Quick-run: use `sim_lab2.do`

After Phase 1 once, the only commands ever needed are:

```tcl
cd {C:/Users/mahaz/Desktop/lab_2_current (3)}
do sim_lab2.do
```

Or from the GUI: **File → Do** → select `sim_lab2.do`.

---

## Test list and simulation time

| Test | Scenario | Sim time (approx) |
|------|----------|--------------------|
| T1  | Correct user password                     | ~2 s  |
| T2  | Wrong user password                       | ~2 s  |
| T3  | Early terminator                          | ~1 s  |
| T4  | 4 failures → locked                       | ~4 s  |
| T5  | Supervisor unlock *(continues from T4)*   | ~5 s  |
| T6  | Timeout *(5 100 clk1ms wait)*            | **~260 s** |
| T7  | Key insert aborts user auth               | ~1 s  |
| T8  | Key removal aborts supervisor auth        | ~2 s  |
| T9  | srst_access mid-entry                     | ~1 s  |
| T10 | Supervisor auth (unlocked)               | ~4 s  |
| T11 | Change user password — success            | ~10 s |
| T12 | Change user password — wrong verify       | ~10 s |
| T13 | Change supervisor password                | ~10 s |

> T6 dominates total runtime (~260 s) because it waits for the hardware 5 000-cycle timeout counter without shortcutting. All other tests complete in under 10 s each.

---

## Expected transcript output

```
[T1] Correct user password → correct + Corr_LED
  PASS [T1] correct fired
  PASS [T1] error silent
  PASS [T1] Corr_LED fired
  PASS [T1] Err_LED silent

[T2] Wrong user password → error + Err_LED
  PASS [T2] error fired
  PASS [T2] correct silent
  PASS [T2] Err_LED fired
  PASS [T2] Corr_LED silent

[T3] Early terminator (only 1 digit) → error
  PASS [T3] error fired
  PASS [T3] correct silent

[T4] 4 wrong attempts → locked; further user auth blocked
  PASS [T4] locked asserted
  PASS [T4] correct blocked while locked

[T5] Supervisor unlocks locked system
  PASS [T5] session_active asserted
  PASS [T5] AP FSM in S3
  PASS [T5] system unlocked
  PASS [T5] session ended after exit

[T6] Timeout during user auth → back to S0 (long sim wait)
  PASS [T6] no correct after timeout
  PASS [T6] no error after timeout
  PASS [T6] AP back to S0

[T7] Supervisor key inserted mid user-auth → abort to S0
  PASS [T7] AP aborted to S0 on key insert

[T8] Supervisor key removed mid supervisor-auth → abort to S0
  PASS [T8] AP aborted to S0 on key removal

[T9] srst_access during user auth → back to S0
  PASS [T9] back to S0 after srst_access

[T10] Supervisor auth while unlocked → S3 session_active
  PASS [T10] session_active
  PASS [T10] AP FSM in S3
  PASS [T10] correct fired

[T11] Change user password — success path
  PASS [T11] cp_active after command
  PASS [T11] verify correct (new pass matches)
  PASS [T11] cp_active cleared after DONE
  PASS [T11] new user password accepted

[T12] Change user password — wrong verify → cp_fail
  PASS [T12] cp_fail: cp_active cleared
  PASS [T12] supervisor session still active

[T13] Change supervisor password — success path
  PASS [T13] cp_active high (super change)
  PASS [T13] verify correct (new super pass)
  PASS [T13] cp_active cleared

══════════════════════════════════════════════════
  ALL 33 CHECKS PASSED
══════════════════════════════════════════════════
```

---

## RAM initial passwords (from `ramm.mif`)

| Region | Address | Password digits |
|--------|---------|-----------------|
| User A  (default active) | 0–4    | `1, 2, 3, 4, 10` |
| User B  (after user swap) | 16–20 | written by T11 |
| Super A (default active) | 32–36 | `2, 0, 2, 6, 10` |
| Super B (after super swap)| 48–52 | written by T13 |

> T11 writes `5,6,7,8,10` to User B and verifies it before `apply_reset`.  
> After `apply_reset`, `user_active` resets to 0 (User A), so the original password is active again.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `# Error: cannot find module lpm_counter` | `lpm_ver` not mapped | Re-run Step 3 |
| `# Error: cannot find module altsyncram` | `altera_mf_ver` not mapped | Re-run Step 4 |
| `correct` never fires in T1 | Wrong user password in `ramm.mif` | Confirm addr 0–4 = `1,2,3,4,10` |
| `correct` never fires in T5 | Wrong supervisor password | Confirm addr 32–36 = `2,0,2,6,10` |
| T4 `locked` never asserts | `ThreeBitsCounter` not reaching 4 | Check `increment` pulses — one per failed attempt |
| T5 `locked` not cleared | `unlock_req` not pulsing | Confirm `supervisor_requests` sees `switches=3` while `session_active=1` |
| T6 never reaches S0 | `timeOut` not firing | Check `ThirteenBitsCounter` waveform — must reach `13'd5000` |
| T11 new password not accepted | `user_active` not flipped | Check `cp_complete` pulse and `apw1/user_active` waveform |
| T11/T12 `cp_active` stuck high | `cp_done` never fires | Check `cp_complete` or `cp_fail` from `change_password` |
| `force` has no effect | Wrong hierarchical path | Confirm path is `uut.switches` / `uut.enter_al` (internal signals, not ports) |
| `# Error: (vlog-2110) Illegal output port` | `.sv` file compiled without `-sv` flag | Add `-sv` to all SystemVerilog compiles |
