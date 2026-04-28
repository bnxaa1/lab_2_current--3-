# Change Password Feature — Original Implementation Plan

> **Superseded.** This document describes the original plan which included COPY states and a 3-region memory scheme. The final implementation uses a 4-region address-swap approach with no COPY phase. See `md/CHANGE_PASSWORD_DESIGN.md` for the current design.

---

## Context

The supervisor can trigger a user-password-change from `supervisor_requests.sv` (via `CHANGE_USER_PASSWORD`). This plan wires that signal into a new `change_password.sv` module that manages the full 3-phase process: entry → verify → copy-to-RAM. Addresses 20–29 are repurposed as temporary storage (the locked-supervisor region is currently unused / dead-end state).

---

## Memory Map (unchanged RAM, 32 addresses × 4 bits)

| Region           | Addresses | `S` value | Note |
|------------------|-----------|-----------|------|
| User password    | 0 – 9     | `2'b00`   | Final write destination |
| Supervisor pass  | 10 – 19   | `2'b01`   | |
| **Temp storage** | 20 – 29   | `2'b10`   | Repurposed for change-password |

---

## New File: `change_password.sv`

### Ports

```sv
module change_password (
    input  logic        clk, resetN,
    input  logic        start,          // from supervisor_requests (CHANGE_USER_PASSWORD)
    input  logic        enter_d,        // clean pulse from lock_validation
    input  logic [3:0]  switches,       // current user input
    input  logic [3:0]  code,           // codeStorage.dataOut (RAM read result)
    input  logic        lv_correct,     // lock_validation correct output
    input  logic        lv_error,       // lock_validation error output
    input  logic        lv_done,        // codeStorage.done (ctr==9)

    output logic        active,         // 1 while change_password is running
    output logic        wren,           // override codeStorage write-enable
    output logic [3:0]  dataIn,         // override codeStorage data input
    output logic [4:0]  wStartAddr,     // override wStartingAddress
    output logic [4:0]  rStartAddr,     // override rStartingAddress
    output logic        clk_en_override,// drives codeStorage.clk_en (replaces enter_d in COPY)
    output logic        ctrRst,         // resets codeStorage counter
    output logic        srst_lv,        // holds lock_validation in reset during ENTRY
    output logic        cp_complete,    // password changed successfully
    output logic        cp_fail         // mismatch, change aborted
);
```

### FSM States

```
IDLE        — wait for start
ENTRY_RST   — pulse ctrRst + srst_lv; set wren=1, wStartAddr=20
ENTRY       — write switches → RAM[20+ctr] on each enter_d
              stop when switches==4'b1010 OR done
VERIFY_RST  — pulse ctrRst + srst_lv; rStartAddr=20
VERIFY_WAIT — one idle cycle for RAM read latency
VERIFY      — rStartAddr=20; let lock_validation run normally
              stop on lv_correct or lv_error
COPY_PREP   — pulse ctrRst; rStartAddr=20, wStartAddr=0, wren=0
COPY_WAIT   — one idle cycle for RAM read latency
COPY        — rStartAddr=20, wStartAddr=0, wren=1, dataIn=code
              clk_en_override=1 (auto-advance every cycle)
              stop when code==4'b1010 OR done
DONE        — assert cp_complete for one cycle → IDLE
ERROR       — assert cp_fail for one cycle → IDLE
```

### Key logic per state

| State       | wren | wStartAddr | rStartAddr | clk_en_override | srst_lv | dataIn  |
|-------------|------|------------|------------|-----------------|---------|---------|
| ENTRY_RST   | 0    | 20         | –          | 0               | 1       | –       |
| ENTRY       | 1    | 20         | –          | enter_d         | 1       | switches|
| VERIFY_RST  | 0    | –          | 20         | 0               | 1       | –       |
| VERIFY_WAIT | 0    | –          | 20         | 0               | 0       | –       |
| VERIFY      | 0    | –          | 20         | enter_d         | 0       | –       |
| COPY_PREP   | 0    | 0          | 20         | 0               | 0       | –       |
| COPY_WAIT   | 0    | 0          | 20         | 0               | 0       | –       |
| COPY        | 1    | 0          | 20         | 1               | 0       | code    |
| DONE/ERROR  | 0    | –          | –          | 0               | 0       | –       |

---

## Modified File: `access_permission.sv`

Add `output logic [2:0] cmd_request_out` port and wire it to the internal `cmd_request` placeholder (prerequisite for connecting `supervisor_requests`). This is **fix #3** from FIXES_NEEDED — S3/S4 also need EXIT_REQUEST transitions added here.

---

## Modified File: `lab_2.sv`

### 1. Instantiate `supervisor_requests`

```sv
supervisor_requests sr1(
    .clk(clk),
    .rstN(resetN),
    .access_state(access_state_p),
    .cmd_request_in(cmd_request_in),  // new top-level input from future UART/Nios-V
    .cmd_request(cmd_request)
);
```

### 2. Instantiate `change_password`

```sv
change_password cp1(
    .clk(clk), .resetN(resetN),
    .start(cmd_request == 3'd1),  // CHANGE_USER_PASSWORD
    .enter_d(enter_d),
    .switches(switches),
    .code(code),
    .lv_correct(correct),
    .lv_error(error),
    .lv_done(done),
    .active(cp_active),
    .wren(cp_wren),
    .dataIn(cp_dataIn),
    .wStartAddr(cp_wStartAddr),
    .rStartAddr(cp_rStartAddr),
    .clk_en_override(cp_clk_en),
    .ctrRst(cp_ctrRst),
    .srst_lv(cp_srst_lv),
    .cp_complete(cp_complete),
    .cp_fail(cp_fail)
);
```

### 3. Mux codeStorage control signals

```sv
assign wren           = cp_active ? cp_wren      : 1'b0;
assign dataIn         = cp_active ? cp_dataIn     : 4'b0;
assign wStartingAddress = cp_active ? cp_wStartAddr : 5'b0;
assign rStartingAddress = cp_active ? cp_rStartAddr
                        : (S == 2'b00) ? 5'b00000
                        : (S == 2'b01) ? 5'b01010 : 5'b10100;
assign cs_clk_en      = cp_active ? cp_clk_en    : enter_d;
assign cs_ctrRst      = cp_active ? cp_ctrRst    : srst;
```

### 4. Mux lock_validation reset

```sv
assign lv_srst = srst || (cp_active && cp_srst_lv);
```

Pass `cs_clk_en`, `cs_ctrRst`, `lv_srst` (instead of the old direct signals) to the respective modules.

---

## Critical Files

| File | Action |
|------|--------|
| `change_password.sv` | **Create** |
| `lab_2.sv` | Instantiate cp1 + sr1, mux 6 signals |
| `access_permission.sv` | Add cmd_request output port, add EXIT_REQUEST transitions in S3/S4 |

---

## Timing Note

The Altera RAM has registered address and output (`address_reg_b = CLOCK0`, `outdata_reg_b = CLOCK0`). The COPY_WAIT and VERIFY_WAIT single-cycle gaps account for this. Verify exact latency in simulation — a second wait cycle may be needed if the RAM configuration introduces 2-cycle read latency.

---

## Verification

1. Simulate: supervisor reaches S3, `cmd_request = CHANGE_USER_PASSWORD`, `start` pulses.
2. ENTRY: enter digits `1,2,3,4,1010` — confirm RAM[20–24] = `{1,2,3,4,1010}`.
3. VERIFY correct: re-enter same sequence — confirm `lv_correct=1` → COPY fires.
4. VERIFY wrong: enter different sequence — confirm `lv_error=1` → ERROR, RAM[0–9] unchanged.
5. COPY: after correct verify, confirm RAM[0–4] = `{1,2,3,4,1010}` matches temp region.
6. Normal login: after change, confirm user can log in with new password `1,2,3,4`.
