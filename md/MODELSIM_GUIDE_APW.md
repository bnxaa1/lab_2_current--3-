# ModelSim Testbench Guide — access_permission_wrapper

Testbench: `tb_access_permission_wrapper.sv`  
DUT: `access_permission_wrapper.sv`  
Script: `sim_apw.do`  
Altera install: `C:\altera_lite\25.1std\`

---

## Overview

The testbench drives `access_permission_wrapper` at 1 kHz (clk1ms) directly —
`clock1` is not instantiated here; it lives only in the top-level `lab_2.sv`.

Running requires two phases:

1. **Library setup** — done **once**; folders are saved to disk and reused.
2. **Compile & simulate** — every time source files change.

`sim_apw.do` automates Phase 2 entirely.

### Key design behaviours under test

- **No start signal** — first digit press IS the first authentication digit; `enter_access = enter_d`
- **Supervisor password** — `2, 0, 2, 6, D` (`4'hD` terminator at addr 36); `rStartingAddress = 6'b100000` (32)
- **S0 does not assert `rst_lv`** — all transitions back to S0 (S1 key interrupt, S1 timeout, S1 correct, S2 key removal, S5 error) assert `rst_lv` for one cycle to reset codeStorage counter and lock_validation FSM
- **`srst_access` full reset** — propagates through `effective_rst_lv = rst_lv | srst_access` in wrapper; resets AP FSM, lock_validation FSM, and codeStorage counter together
- **Timeout counter** — resets to 0 on S0→S1 only (user auth start); supervisor path (S2) has no timeout
- **`enter_d` gate** — blocked when `locked && !key`; prevents codeStorage counter advances and lock_validation FSM transitions while the system is locked and no supervisor key is present
- **`apply_reset`** — pulses `rst_failureCtr` after releasing `resetN` to clear `ThreeBitsCounter` (no `aclr` port on IP); use `apply_reset` whenever locked state must be cleared between tests

---

## Phase 1 — Compile Altera Simulation Libraries (once only)

If you already ran Phase 1 for `tb_lock_validation_wrapper` in the same project
folder, skip this phase — the libraries are already there.

| Library | Provides |
|---|---|
| `lpm_ver` | `lpm_counter` — used by `counter`, `thirteenBitsCtr`, `ThreeBitsCounter` |
| `altera_mf_ver` | `altsyncram` — used by the `ram` IP |
| `altera_ver` | Altera device primitives |
| `sgate_ver` | Internal gate primitives |
| `altera_lnsim_ver` | Cyclone V synthesis models |

### Step 1 — Open ModelSim

Launch from the Start menu or from Quartus: **Tools → Run Simulation Tool → RTL Simulation**

### Step 2 — Set the working directory

```tcl
cd {C:/Users/mahaz/Desktop/lab_2_current (3)}
```

### Step 3 — Create the work library

```tcl
vlib work
vmap work work
```

### Step 4 — Create and compile `lpm_ver`

```tcl
vlib lpm_ver
vmap lpm_ver lpm_ver
vlog -work lpm_ver {C:/altera_lite/25.1std/quartus/eda/sim_lib/220model.v}
```

### Step 5 — Create and compile `altera_mf_ver`

```tcl
vlib altera_mf_ver
vmap altera_mf_ver altera_mf_ver
vlog -work altera_mf_ver {C:/altera_lite/25.1std/quartus/eda/sim_lib/altera_mf.v}
```

### Step 6 — Create and compile `altera_ver`

```tcl
vlib altera_ver
vmap altera_ver altera_ver
vlog -work altera_ver {C:/altera_lite/25.1std/quartus/eda/sim_lib/altera_primitives.v}
```

### Step 7 — Create and compile `sgate_ver`

```tcl
vlib sgate_ver
vmap sgate_ver sgate_ver
vlog -work sgate_ver {C:/altera_lite/25.1std/quartus/eda/sim_lib/sgate.v}
```

### Step 8 — Create and compile `altera_lnsim_ver`

```tcl
vlib altera_lnsim_ver
vmap altera_lnsim_ver altera_lnsim_ver
vlog -sv -work altera_lnsim_ver {C:/altera_lite/25.1std/quartus/eda/sim_lib/altera_lnsim.sv}
```

> Libraries are now folders in the project directory. Phase 1 never needs to be repeated
> unless Quartus is reinstalled or the project is moved.

---

## Phase 2 — Compile Design Files and Run Simulation

Repeat this phase every time you edit source files. Or just run `sim_apw.do`.

### Step 9 — Compile Altera IP files (Verilog)

`TwentyBitsCounter` is **not needed** — `access_permission_wrapper` uses
`thirteenBitsCtr` and `ThreeBitsCounter` only.  
`sixteenbitsctr` / `clock1` are **not needed** — the testbench drives `clk` directly.

```tcl
vlog -work work counter.v
vlog -work work thirteenBitsCtr.v
vlog -work work ThreeBitsCounter.v
vlog -work work ram_sim.v
```

### Step 10 — Compile design files (SystemVerilog, dependency order)

```tcl
vlog -sv -work work one_pulse_generator.sv
vlog -sv -work work codeStorage.sv
vlog -sv -work work lock_validation.sv
vlog -sv -work work lock_validation_wrapper.sv
vlog -sv -work work access_permission.sv
vlog -sv -work work access_permission_wrapper.sv
```

### Step 11 — Compile testbench

```tcl
vlog -sv -work work tb_access_permission_wrapper.sv
```

### Step 12 — Launch simulation

```tcl
vsim -t 1ns \
     -L lpm_ver \
     -L altera_mf_ver \
     -L altera_ver \
     -L sgate_ver \
     -L altera_lnsim_ver \
     work.tb_access_permission_wrapper
```

### Step 13 — Add waveforms

```tcl
add wave -divider "TB Control"
add wave /tb_access_permission_wrapper/clk
add wave /tb_access_permission_wrapper/resetN
add wave /tb_access_permission_wrapper/srst_access
add wave /tb_access_permission_wrapper/key

add wave -divider "Inputs"
add wave /tb_access_permission_wrapper/enter_al
add wave /tb_access_permission_wrapper/switches

add wave -divider "Outputs"
add wave /tb_access_permission_wrapper/correct
add wave /tb_access_permission_wrapper/error
add wave /tb_access_permission_wrapper/Corr_LED
add wave /tb_access_permission_wrapper/Err_LED
add wave /tb_access_permission_wrapper/locked
add wave /tb_access_permission_wrapper/timeOut
add wave /tb_access_permission_wrapper/state_p

add wave -divider "Internal – access_permission"
add wave /tb_access_permission_wrapper/dut/ap1/state_reg
add wave /tb_access_permission_wrapper/dut/rst_lv
add wave /tb_access_permission_wrapper/dut/effective_rst_lv
add wave /tb_access_permission_wrapper/dut/increment
add wave /tb_access_permission_wrapper/dut/ap_rst_timeoutCtr

add wave -divider "Internal – timeout counter"
add wave /tb_access_permission_wrapper/dut/ThirteenBitsCounter
add wave /tb_access_permission_wrapper/dut/rst_timeoutCtr

add wave -divider "Internal – lock_validation_wrapper"
add wave /tb_access_permission_wrapper/dut/lvw1/u_lock_validation/state_reg
add wave /tb_access_permission_wrapper/dut/lvw1/enter_d_raw
add wave /tb_access_permission_wrapper/dut/enter_d
add wave /tb_access_permission_wrapper/dut/lvw1/done
add wave /tb_access_permission_wrapper/dut/lvw1/code
add wave /tb_access_permission_wrapper/dut/rStartingAddress

add wave -divider "Failure counter"
add wave /tb_access_permission_wrapper/dut/threeBitsCounter
```

### Step 14 — Run simulation

```tcl
run -all
```

The transcript prints pass/fail for each test.  
Press **F4** (or **View → Wave**) to open the waveform viewer.

---

## Quick-run: use `sim_apw.do`

`sim_apw.do` in the project root combines Steps 9–14.
After Phase 1 is done once, you only ever need:

```tcl
cd {C:/Users/mahaz/Desktop/lab_2_current (3)}
do sim_apw.do
```

Or from the GUI: **File → Do** → select `sim_apw.do`.

---

## Test cases

| # | Sequence | Expected result |
|---|---|---|
| 1 | `1, 2, 3, 4, D (4'hD)` | `correct=1`, `Corr_LED=1` |
| 2 | `9, D (4'hD)` | `error=1`, `Err_LED=1` (wrong first digit) |
| 3 | `1, 2, 3, 4, 9, D (4'hD)` | `error=1` (correct digits, wrong at end-marker position) |
| 4 | `D (4'hD)` immediately | `error=1` (early end marker at digit 0) |
| 5 | `1, 9, D (4'hD)` | `error=1` (first correct, second wrong) |
| 6 | `1, 2`, `key=1`, `key=0`, then `1, 2, 3, 4, D (4'hD)` | `correct=1` (key interrupt, clean recovery) |
| 7 | `key=1`, `0`, `key=0`, then `1, 2, 3, 4, D (4'hD)` | `correct=1` (supervisor key removal, clean recovery) |
| 8 | `1, 2`, `srst_access`, then `1, 2, 3, 4, D (4'hD)` | `correct=1` (mid-entry full reset via `effective_rst_lv`) |
| 9 | 4× `9, D (4'hD)` | `locked=1` after 4th failure |
| 9b | user digits while `locked=1` | `correct=0`, `error=0` (`enter_d` gate blocks all presses) |
| 9c | `rst_failureCtr` pulse, then `1, 2, 3, 4, D (4'hD)` | `correct=1` (counter still at 0 after blocked presses) |
| 10 | `1`, then 5100 idle cycles | `state_p=0` (timeout → S0) |
| 11 | `key=1`, `2, 0, 2, 6, D (4'hD)` (not locked) | `correct=1`, `state_p=3` (S3, supervisor session) |
| 12 | 4× `9, D` → lock, then `key=1`, `2, 0, 2, 6, D` | `correct=1`, `state_p=3` (S3; S4 merged into S3, locked vs unlocked discriminated by `input_cond[2]` inside S3) |

> **Test 10 runtime:** 5100 cycles × 1 ms = 5.1 s of simulated time.
> ModelSim will take a few seconds of real CPU time for this test alone. Let it complete.

> **Tests 11 & 12:** The AP FSM stays in S3 after authentication. Exit is via `apply_reset` (clears AP FSM via `srst_access`). In the full `lab_2` testbench, `supervisor_requests` handles exit via `exit_req`.

---

## RAM contents (ramm.mif)

| Region | `rStartingAddress` | Digits | Correct entry |
|---|---|---|---|
| User A (`key=0`) | `6'b000000` (0) | addr 0–4: `1, 2, 3, 4, 13` | `1, 2, 3, 4, D` (5 presses) |
| Supervisor A (`key=1`) | `6'b100000` (32) | addr 32–36: `2, 0, 2, 6, 13` | `2, 0, 2, 6, D` (5 presses) |

The end-of-code marker is `4'hD` = 13 (stored at addr 4 for user A and addr 36 for supervisor A).

---

## Timing reference

| Parameter | Value |
|---|---|
| `clk` period | 1 ms (1 kHz) |
| `one_pulse_generator` debounce | 15 clk cycles = 15 ms |
| `PRESS_CYCLES` / `RELEASE_CYCLES` | 20 each → 40 ms per digit |
| 5-digit user password | 5 × 40 ms = 200 ms simulated |
| 5-digit supervisor password | 5 × 40 ms = 200 ms simulated |
| Timeout threshold | 5 000 cycles = 5 s (user only; no timeout in S2) |
| `apply_reset` sequence | 3 cycles `resetN=0`, 1 cycle overhead, 2 cycles `rst_failureCtr=1`, 3 cycles settle |
| `sync_reset` sequence | 2 cycles `srst_access=1`, 5 cycles settle |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Error: cannot find module lpm_counter` | `lpm_ver` not mapped | Re-run Steps 4 and 12 |
| `Error: cannot find module altsyncram` | `altera_mf_ver` not mapped | Re-run Steps 5 and 12 |
| `Error: cannot find module altera_lnsim` | `altera_lnsim_ver` not compiled | Re-run Steps 8 and 12 |
| Test 1 `FAIL` — `correct` never fires | Counter didn't advance on press 1 | Confirm `rst_lv` is NOT unconditionally asserted in `access_permission.sv` S0; all S→S0 transitions must assert it instead |
| Test 8 `FAIL` — `correct` never fires after `sync_reset` | `srst_access` not resetting codeStorage counter | Confirm `access_permission_wrapper.sv` has `assign effective_rst_lv = rst_lv \| srst_access` and `lvw1.rst_lv` is wired to `effective_rst_lv` |
| Test 9 `FAIL` — `locked` never asserts | `increment` not firing or `ThreeBitsCounter` not advancing | Confirm `access_permission.sv` S1 sets `increment=1` on `error`; confirm `rst_failureCtr=0` throughout test 9 |
| Test 9 `FAIL` — `locked` fires too early | `increment` fires in a state other than S1 | Confirm only S1 drives `increment=1` |
| Test 9b `FAIL` — `error` fires while locked | `enter_d` gate not working | Confirm `lock_validation_wrapper.sv` has `assign enter_d = enter_d_raw && (!locked \| key)` |
| Test 9c `FAIL` — `correct` not seen after unlock | Counter advanced during blocked presses in 9b | `enter_d` gate check above; verify `enter_d_raw` vs `enter_d` waveform divergence while locked |
| Tests 10–12 fail with `locked=1` | `apply_reset` not clearing `ThreeBitsCounter` | Confirm `apply_reset` pulses `rst_failureCtr=1` after `resetN=1` |
| Test 11/12 `FAIL` — `correct` never fires | Supervisor RAM mismatch or rStartingAddress wrong | Confirm `ramm.mif` addr 32–36 = `2,0,2,6,13`; confirm `rStartingAddress = 6'b100000` (32) for `key=1` in wrapper |
| Test 12 setup `FAIL` — system not locked before supervisor auth | Failure counter not incrementing | Confirm `access_permission.sv` S1 sets `increment=1` on error and `ThreeBitsCounter` is connected |
| `Error: (vlog-2110) Illegal output port` | `.sv` file compiled without `-sv` flag | Add `-sv` to all SystemVerilog `vlog` commands |
| Simulation hangs at Test 10 | Normal — 5100 cycles takes a few CPU seconds | Wait; do not interrupt |
