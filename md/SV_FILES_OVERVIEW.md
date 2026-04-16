# SystemVerilog Files Overview

This document explains the purpose of each `.sv` file in the project, the design idea behind it, and how the files relate to each other.

---

## High-level design idea

This project is building a digital lock / access-control style system.
The logic is split into smaller modules so that each file handles one clear responsibility:

- **input conditioning**: turning a mechanical button press into a clean one-cycle pulse
- **lock validation**: checking whether the entered sequence is correct
- **access policy / output control**: deciding what LEDs or status outputs should do
- **storage**: holding password or temporary code data in RAM

This separation is useful because it keeps each FSM or data-path block focused on one job instead of mixing all behaviors in one large file.

---

## Files currently used in the Quartus project

According to `lab_2.qsf`, these SystemVerilog files are part of the active project:

- `lab_2.sv`
- `one_pulse_generator.sv`
- `access_permission.sv`
- `access_permission_wrapper.sv`
- `supervisor_requests.sv`
- `codeStorage.sv`
- `lock_validation.sv`

There are also additional `.sv` files under `first trial/` which look like earlier archived versions.

---

## 1) `lab_2.sv`

### What it does
This file is the **top-level integration module** for the input-conditioning and validation path.

### Main logic behind it
Its job is only to **connect submodules together**:

- it instantiates `lock_validation` as the main validation block
- it instantiates `codeStorage` to supply the stored code and `done` signal
- it instantiates `access_permission_wrapper` to generate policy/control signals such as `srst`, `S`, `Err_LED`, and `Corr_LED`
- `lock_validation` now internally instantiates `one_pulse_generator`

The validation state output (`state_regt`) and access mode signal (`S`) are kept as **internal signals** inside `lab_2.sv` instead of being exposed as top-level outputs.

### Why this file exists
The rationale is architectural cleanliness:
- `one_pulse_generator.sv` should not know anything about lock rules
- `lock_validation.sv` should not know how the pushbutton is debounced
- `lab_2.sv` becomes the place where both independent blocks are wired together

This is a better hierarchy because it keeps each child module single-purpose.

### Relationship to other files
- **instantiates** `codeStorage.sv`
- **instantiates** `access_permission_wrapper.sv`
- **instantiates** `lock_validation.sv`
- is the active **top-level entity** in `lab_2.qsf`

---

## 2) `one_pulse_generator.sv`

### What it does
This module generates a **debounced one-pulse signal** from the active-low enter button (`enter_al`).

### Main logic behind it
Mechanical buttons do not produce a perfectly clean transition. When pressed, they may bounce and produce multiple quick transitions. If the design directly used that raw signal, the system could count one press multiple times.

So this file exists to:

1. **filter / qualify the button press** using a small FSM and a counter
2. **generate exactly one pulse** (`enter_d`) for a valid press
3. **provide that clean pulse** as an output for whatever higher-level module needs it

### Internal structure
- FSM states `S0` to `S4` manage the press/release sequence
- A `counter` instance is used as a timing element
- `done_clk = &ctr` detects when the debounce wait interval has completed
- `enter_d` becomes the clean one-cycle pulse that other modules can trust

### Why this file is separate
The rationale is modularity:
- **button handling** is different from **password checking**
- splitting them makes the design easier to debug and easier to change
- the same one-pulse logic could be reused elsewhere if needed

### Relationship to other files
- **uses** `counter` IP/module
- is **instantiated by** `lock_validation.sv`
- acts like the front-end of the lock-entry pipeline

---

## 3) `lock_validation.sv`

### What it does
This file contains the FSM that decides whether the entered lock sequence is valid or invalid.

### Main logic behind it
The purpose of this module is to keep **all password/sequence checking rules** in one place.
It receives:

- the raw enter input `enter_al`
- the synchronous reset input `srst`
- the current expected code value `code` (currently supplied from `codeStorage` through `lab_2.sv`)
- the current user-entered value `switches`
- a `done` indication

and produces:

- `enter_d`
- `correct`
- `error`
- `state_regt` for visibility/debugging

### Current FSM interpretation
The current version uses a 4-state approach:

- **S0**: still correct so far
- **S1**: success state, asserts `correct`
- **S2**: an error or incomplete ending has happened, so wait for the attempt to finish
- **S3**: failure state, asserts `error`

### Important design idea
This file now owns the full validation path input side: it internally generates `enter_d` using `one_pulse_generator`, then uses that clean pulse in the validation FSM.
It also supports a synchronous reset path through `srst`, allowing the validation FSM to return to `S0` on a clock edge without requiring the asynchronous reset.

### Why this file exists separately
The rationale is separation of concerns:
- `one_pulse_generator.sv` still handles **how input is captured**
- `lock_validation.sv` handles **what the input means**, while embedding the pulse generator it depends on

This makes it easier to change the password-checking algorithm without touching the debounce logic.

### Relationship to other files
- **instantiated in** `lab_2.sv`
- **instantiates** `one_pulse_generator.sv`
- logically feeds status signals into higher-level control logic such as `access_permission.sv`

---

## 4) `access_permission.sv`

### What it does
This module is a **control FSM for access results, user access flow, and supervisor access flow**.
It decides what happens after the system learns whether an attempt was correct or wrong.

### Main logic behind it
This file is not comparing the code itself. Instead, it uses already-generated status inputs such as:

- `correct`
- `error`
- `locked`
- `timeOut`
- `key`
- `enter`
- `srst_access` (synchronous reset for the access-permission FSM)

and turns them into system-level control outputs such as:

- `Err_LED`
- `Corr_LED`
- `increment` (likely failure count increment)
- `srst` (reset for timeout/counter logic)
- `S` (region / mode selection signal used by other logic)

### Design rationale
This file expresses the **access policy** of the system.

In other words:
- `lock_validation.sv` answers: **was the entry right or wrong?**
- `access_permission.sv` answers: **what should the overall system do next?**

This is a good architectural split because policy logic often changes independently from the lower-level checking logic.

### Observed behavior from the FSM
The module appears to:
- wait for certain combinations of `locked`, `key`, and `enter`
- distinguish between normal user entry and supervisor entry
- use a shared supervisor authentication state
- move to true supervisor unlocked / locked states after successful supervisor authentication
- react differently to success vs failure
- control timeout reset behavior
- increment a failure-related signal when authentication fails on the user path
- support a named synchronous reset path (`srst_access`) back to `S0`

### Relationship to other files
- conceptually consumes results from `lock_validation.sv`
- may work with counters/timers outside this file
- acts as a system supervisor for access outcome handling

---

## 5) `access_permission_wrapper.sv`

### What it does
This file is a wrapper around `access_permission.sv` that provides the support logic needed for the `locked` and `timeOut` inputs.

### Main logic behind it
The wrapper instantiates `access_permission` and builds the missing environment around it:

- a **20-bit timeout counter**
- a **3-bit failure counter**

The intended behavior is:

- `timeOut = 1` when `twentyBitsCounter == 1000000`
- the 20-bit timeout counter is cleared by `srst`
- `locked = 1` when `threeBitsCounter == 4`
- the 3-bit failure counter increments when `increment = 1`
- the 3-bit failure counter is cleared by `srst1`

### Why this file exists
The rationale is to avoid putting timer and lockout counting logic directly inside `access_permission.sv`.
`access_permission.sv` stays focused on policy/state transitions, while the wrapper provides the counter-based conditions it depends on.

### Relationship to other files
- **instantiates** `access_permission.sv`
- generates the `timeOut` and `locked` signals consumed by `access_permission.sv`
- exposes `increment`, `srst`, `S`, and the access-permission outputs to `lab_2.sv`

---

## 6) `supervisor_requests.sv`

### What it does
This file is a small supervisor-session request block intended to keep supervisor command requests outside `access_permission.sv`.

### Main logic behind it
- `clk`
- `rstN`
It takes:
- the current `access_permission` state
- a compact `cmd_request`-style input from a future UART/Nios-V black-box decoder

and converts them into a compact `cmd_request[1:0]` signal with meanings like:
and converts them into a compact `cmd_request[2:0]` signal with meanings like:
- `0` = no request
- `1` = change user password
- `2` = exit
- `3` = unlock
- `4` = change supervisor password

### Why this file exists
The rationale is to keep `access_permission.sv` focused on policy states while moving supervisor requests into a separate module.

### Current note
At the moment this file is a small FSM. Once a valid supervisor request is accepted, it stays in that request state until reset or an exit request occurs. The idea is that a future UART/Nios-V black-box decoder provides a compact request code directly, and this file latches and filters it based on the current access-permission state.

---

## 7) `codeStorage.sv`

### What it does
This module provides a simple **RAM access wrapper with automatic address stepping**.

### Main logic behind it
The file combines:

- a `ram` instance for data storage
- a `counter` instance for address progression

It computes:

- `rdaddress = rStartingAddress + ctr`
- `wraddress = wStartingAddress + ctr`

So instead of manually supplying every read/write address, the design can provide a starting point and let the internal counter step through successive locations.

### Why this is useful
This is especially helpful for passwords or code sequences because they are multi-digit values stored across multiple memory addresses.

The rationale behind this file is:
- simplify sequential reading/writing of code digits
- avoid repeating address increment logic elsewhere
- isolate memory-management details from the rest of the design

### Current note from comments
The comments suggest this memory may be intended for:
- temporary password storage
- storing a new password before verification
- handling variable password length
- possibly using `1010` as an end-of-code marker

So this file is likely the data-storage side of a larger password-management feature.

### Relationship to other files
- **uses** `ram` IP/module
- **uses** `counter` IP/module
- in the current top-level wiring, it supplies `code` and `done` into `lock_validation.sv`
- its `clk_en` is driven by `enter_d`, so the stored-code address advances once per debounced enter pulse
- supports higher-level password entry or password update logic
---

## Design relationships summary

### Active logic flow
In terms of system intent, the flow is roughly:

1. **User input arrives from button/switches**
2. `lab_2.sv` uses `codeStorage.sv` to provide the stored code value and the `done` indication
3. `lab_2.sv` forwards those signals to `lock_validation.sv`
4. inside `lock_validation.sv`, `one_pulse_generator.sv` cleans the enter button and creates `enter_d`
5. `enter_d` is also used as `codeStorage`'s `clk_en`, so code storage advances once per valid entry pulse
6. `lock_validation.sv` checks whether the entered sequence is correct
7. `lab_2.sv` derives an access-enter condition `enter_d && (switches == 11)` and sends it to `access_permission_wrapper.sv`
8. `access_permission_wrapper.sv` builds the timeout and lock counters around `access_permission.sv`
9. `access_permission.sv` decides how the system should react to success/failure and includes true supervisor session states
10. `supervisor_requests.sv` is reserved to translate supervisor commands using those true supervisor states (`S3`/`S4`)

---

## Why this overall structure makes sense

The project is organized around **functional responsibility**:

- **top-level wiring** → `lab_2.sv`
- **signal conditioning** → `one_pulse_generator.sv`
- **verification logic** → `lock_validation.sv`
- **access wrapper / derived conditions** → `access_permission_wrapper.sv`
- **system reaction / policy** → `access_permission.sv`
- **supervisor request handling** → `supervisor_requests.sv`
- **memory / sequence storage** → `codeStorage.sv`

This is a good hardware-design pattern because it:
- improves readability
- reduces coupling between unrelated logic
- makes testing easier
- allows each FSM or block to evolve independently

---

## Notes

- The current Quartus top-level entity in `lab_2.qsf` is set to **`lab_2`**, which now serves as the integration layer between the one-pulse generator and the lock validator.
- The `first trial/` files appear to be historical reference versions rather than the main active implementation.
- Backup files with `.bak` extensions are not covered here because they are not `.sv` source files.

---

## Code Review Notes

### 1. Debounce counter too short — `one_pulse_generator.sv`

`counter` is a 4-bit IP (`lpm_width = 4`). `done_clk = &ctr` fires when `ctr = 4'b1111 = 15`. At 50 MHz that is **300 ns** — far too short to debounce a physical button (needs ~10–20 ms ≈ 500K–1M cycles). A wider dedicated debounce counter is needed, similar to `TwentyBitsCounter`.

### 2. `supervisor_requests.sv` is never instantiated

The module exists and is listed in the QSF but is wired to nothing. `lab_2.sv` never instantiates it and `access_permission` has no `cmd_request` input port. It is completely disconnected from the design.

### 3. States S3/S4 in `access_permission` are dead-end states — `access_permission.sv`

Once the FSM enters a supervisor session (S3 or S4), the only exit is `rstN` or `srst_access`. There are no internal transitions out. The comment on S3 acknowledges this (`// move it later to supervisor requests`) but since `supervisor_requests` is not connected, there is currently no way to exit a supervisor session gracefully.

### 4. `srst1` hardwired to 0 — `lab_2.sv` line 17

The failure counter (`ThreeBitsCounter`) in `access_permission_wrapper` never resets. Once `locked = 1` (4 failures), the only recovery is a full `resetN`. The TODO comment acknowledges this but also means the supervisor path cannot clear the lockout, which defeats its purpose.

### 5. Write path permanently disabled — `lab_2.sv` line 12

`wren = 1'b0` and `dataIn = 4'b0` are hardcoded. Password changing is completely unimplemented. The comment block at the bottom of `codeStorage.sv` describes the intended behaviour but none of it is wired up yet.

### 6. `done = 1` persists into S2 in `lock_validation`

When `done = 1` (ctr = 9) and the digit is wrong, the FSM goes to S2. But `done` is still 1 in S2 (ctr has not changed), so the very next `enter_d` immediately transitions to S3 — the user gets no extra entry chance at max length. This may be intentional but is worth confirming.

### 7. Magic number in `enter_access` — `lab_2.sv` line 16

```sv
assign enter_access = enter_d && (switches == 4'd11);
```

`4'd11` (`4'b1011`) is undocumented. It is unclear why 11 specifically triggers the access-permission path. A named parameter or constant would make the intent explicit.

### 8. S2 and S3 share the same memory region — `access_permission.sv`

Both supervisor authentication (S2) and the unlocked supervisor session (S3) drive `S = 2'b01`, pointing to RAM region starting at address 10. S4 (locked supervisor session) drives `S = 2'b10` (address 20). It is not documented why the locked supervisor session requires a different memory region — this needs a clear design decision on what each region stores.

### 9. Timeout counter width — `access_permission_wrapper.sv`

The current 20-bit counter reaches 1,000,000 cycles ≈ **20 ms** at 50 MHz. For a 5-second timeout the target count is 250,000,000 cycles, which requires a **28-bit counter** (`2^28 = 268,435,456 > 250,000,000`). `TwentyBitsCounter` must be replaced with a 28-bit variant and the compare value updated to `28'd250_000_000`.

### Summary table

| # | File | Severity | Issue |
|---|---|---|---|
| 1 | `one_pulse_generator.sv` | **High** | 4-bit debounce = 15 cycles, too short for real hardware |
| 2 | `lab_2.sv` | **High** | `supervisor_requests` not instantiated |
| 3 | `access_permission.sv` | **High** | S3/S4 are dead-end states with no exit |
| 4 | `lab_2.sv` line 17 | **High** | `srst1 = 0` means lockout is permanent |
| 5 | `lab_2.sv` line 12 | Medium | Write path (`wren = 0`) unimplemented |
| 6 | `lock_validation.sv` | Low | `done = 1` in S2 forces immediate error on next press |
| 7 | `lab_2.sv` line 16 | Low | Magic number `switches == 11` undocumented |
| 8 | `access_permission.sv` | Low | S2 and S3 share same memory region `S = 01` |
| 9 | `access_permission_wrapper.sv` | Medium | 20-bit counter too narrow for 5 s timeout; needs 28 bits |
