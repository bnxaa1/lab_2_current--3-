# ModelSim Testbench — Step-by-Step Guide

Testbench: `tb_lock_validation_wrapper.sv`  
DUT: `lock_validation_wrapper.sv`  
Altera install: `C:\altera_lite\25.1std\`

---

## Overview

Running the testbench requires two phases:

1. **Library setup** (done once — libraries are saved to disk and reused)
2. **Compile & simulate** (every time you change source files)

A ready-to-run script `sim.do` covers both phases automatically.

---

## Phase 1 — Compile Altera Simulation Libraries (once only)

These libraries provide the simulation models for:

| Library | Provides |
|---|---|
| `lpm_ver` | `lpm_counter` — used by all counter IPs (`counter`, `sixteenbitsctr`, `thirteenBitsCtr`, `ThreeBitsCounter`, `TwentyBitsCounter`) |
| `altera_mf_ver` | `altsyncram` — used by the `ram` IP |
| `altera_ver` | Altera device primitives |
| `sgate_ver` | Internal gate primitives |
| `altera_lnsim_ver` | Cyclone V synthesis models (required for Cyclone V target) |

### Step 1 — Open ModelSim

Launch ModelSim from the Start menu or from inside Quartus:
**Tools → Run Simulation Tool → RTL Simulation**

### Step 2 — Set the working directory

In the ModelSim transcript (bottom console), navigate to the project folder:

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

> After this step the libraries exist as folders in your project directory. You never need to repeat Phase 1 unless you reinstall Quartus or move the project.

---

## Phase 2 — Compile Design Files and Run Simulation

Run these steps every time you change source files. Or just run `sim.do` (see section below).

### Step 9 — Compile Altera IP files (Verilog)

Order does not matter between IPs but all must be compiled before the SV design files.

```tcl
vlog -work work counter.v
vlog -work work sixteenbitsctr.v
vlog -work work thirteenBitsCtr.v
vlog -work work ThreeBitsCounter.v
vlog -work work TwentyBitsCounter.v
vlog -work work ram.v
```

### Step 10 — Compile design files (SystemVerilog, dependency order)

```tcl
vlog -sv -work work clock1.sv
vlog -sv -work work one_pulse_generator.sv
vlog -sv -work work codeStorage.sv
vlog -sv -work work lock_validation.sv
vlog -sv -work work lock_validation_wrapper.sv
```

### Step 11 — Compile testbench

```tcl
vlog -sv -work work tb_lock_validation_wrapper.sv
```

### Step 12 — Launch simulation

```tcl
vsim -t 1ns \
     -L lpm_ver \
     -L altera_mf_ver \
     -L altera_ver \
     -L sgate_ver \
     -L altera_lnsim_ver \
     work.tb_lock_validation_wrapper
```

### Step 13 — Add waveforms

```tcl
add wave -divider "TB Control"
add wave /tb_lock_validation_wrapper/clk
add wave /tb_lock_validation_wrapper/resetN
add wave /tb_lock_validation_wrapper/srst

add wave -divider "Inputs"
add wave /tb_lock_validation_wrapper/enter_al
add wave /tb_lock_validation_wrapper/switches

add wave -divider "Outputs"
add wave /tb_lock_validation_wrapper/correct
add wave /tb_lock_validation_wrapper/error

add wave -divider "Internal"
add wave /tb_lock_validation_wrapper/dut/clk1ms
add wave /tb_lock_validation_wrapper/dut/enter_d
add wave /tb_lock_validation_wrapper/dut/done
add wave /tb_lock_validation_wrapper/dut/code
```

### Step 14 — Run simulation

```tcl
run -all
```

The transcript will print pass/fail messages for each of the 5 tests.  
Press **F4** (or View → Wave) to open the waveform viewer.

---

## Quick-run: use `sim.do`

A script file `sim.do` in the project root combines Steps 9–14.  
After doing Phase 1 once, you only ever need:

```tcl
cd {C:/Users/mahaz/Desktop/lab_2_current (3)}
do sim.do
```

Or from the ModelSim GUI: **File → Do** → select `sim.do`.

---

## Expected transcript output

```
=== tb_lock_validation_wrapper ===
[...] Reset done
[...] Test 1: correct sequence  1-2-3-4-1010
[...] >> CORRECT asserted
[...] Test 1 PASS
[...] Test 2: wrong digit  9-1010
[...] >> ERROR asserted
[...] Test 2 PASS
[...] Test 3: correct digits, wrong end  1-2-3-4-9
[...] >> ERROR asserted
[...] Test 3 PASS
[...] Test 4: early end marker  1010 at digit 0
[...] >> ERROR asserted
[...] Test 4 PASS
[...] Test 5: srst mid-entry, then correct sequence
[...] >> CORRECT asserted
[...] Test 5 PASS
=== simulation complete ===
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `# Error: cannot find module lpm_counter` | `lpm_ver` library not mapped | Rerun steps 4 and 12 |
| `# Error: cannot find module altsyncram` | `altera_mf_ver` not mapped | Rerun steps 5 and 12 |
| `# Error: cannot find module altera_lnsim` | `altera_lnsim_ver` not compiled | Rerun steps 8 and 12 |
| `correct` never fires | Wrong digit values — check `ramm.mif` contents | User password is `1,2,3,4,1010` |
| Simulation runs too slowly | Normal — each digit takes ~40 ms simulated time (debounce) | Let it complete; 5 tests ≈ 4 s simulated time |
| Tests 2–5 show wrong result | `srst` held too short — FSM/ctr never reset between tests | `sync_reset` must hold `srst` for ≥ 2 ms (2 × `clk1ms`) so `clk1ms`-domain FF captures it; fixed in `tb_lock_validation_wrapper.sv` |
| Test 1 starts with wrong `ctr` | `resetN` held too short in `apply_reset` — `codeStorage.ctr` never cleared | `resetN` must be held low for ≥ 2 ms; `codeStorage` has no async reset — `sclr` only fires at `clk1ms` posedge; fixed in `tb_lock_validation_wrapper.sv` |
| `# Error: (vlog-2110) Illegal output port` | `.sv` file compiled with `vlog` without `-sv` flag | Add `-sv` flag to all `.sv` compiles |
