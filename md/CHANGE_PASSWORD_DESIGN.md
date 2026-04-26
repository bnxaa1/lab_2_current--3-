# Change Password — Design

## Memory Layout (address-swap approach)

| addr[5:4] | Region | Addresses | Identity |
|---|---|---|---|
| `2'b00` | User region A | 0–15 | User (default active) |
| `2'b01` | User region B | 16–31 | User (swap target) |
| `2'b10` | Supervisor region A | 32–47 | Supervisor (default active) |
| `2'b11` | Supervisor region B | 48–63 | Supervisor (swap target) |

Each region holds up to 10 digits (counter 0–9). Only 16 slots are allocated per region so bit 4 is the clean swap bit with no overflow risk (counter max = 9 < 16).

Inactive region address = active region address XOR `6'b010000` (flip bit 4 only).

---

## Why Address Swap Instead of Copy

During a COPY phase, a power failure mid-write leaves the active password region partially overwritten and corrupted. The address-swap approach never touches the active region during password entry or verification — the new password is written entirely to the inactive region first. Only when verification succeeds does the active pointer flip, which is a single register write and atomic.

---

## FSM (change_password.sv)

```
IDLE → ENTRY_RST → ENTRY → VERIFY_RST → VERIFY_WAIT → VERIFY → DONE / ERROR
```

COPY_PREP, COPY_WAIT1, COPY_WAIT2, and COPY states from the original design are removed entirely.

| State | Action |
|---|---|
| IDLE | Wait for `start` pulse |
| ENTRY_RST | Assert `ctrRst`, `srst_lv`; set `wStartAddr = inactive_addr` (1 cycle) |
| ENTRY | Write `switches` to inactive region on each `enter_d`; `srst_lv=1`; exit on `switches==1010` or `done` |
| VERIFY_RST | Assert `ctrRst`, `srst_lv`; set `rStartAddr = inactive_addr` (1 cycle) |
| VERIFY_WAIT | Hold `rStartAddr = inactive_addr` (1 cycle RAM read latency) |
| VERIFY | `rStartAddr = inactive_addr`; lock_validation compares re-entry against written digits; exit on `lv_correct` or `lv_error` |
| DONE | Assert `cp_complete` for 1 cycle → IDLE |
| ERROR | Assert `cp_fail` for 1 cycle → IDLE |

---

## Ports

```sv
module change_password (
    input  logic        clk, resetN,
    input  logic        start,           // 1-cycle pulse from supervisor_requests
    input  logic        enter_d,         // debounced keypress
    input  logic [3:0]  switches,        // digit input
    input  logic        lv_correct,      // lock_validation correct output
    input  logic        lv_error,        // lock_validation error output
    input  logic        done,            // codeStorage counter at 9 (max digits)
    input  logic [5:0]  active_addr,     // current active region start address from wrapper
    output logic        cp_active,       // 1 while running; mux selector in lab_2
    output logic        wren,
    output logic [3:0]  dataIn,
    output logic [5:0]  wStartAddr,      // inactive region (write target during ENTRY)
    output logic [5:0]  rStartAddr,      // inactive region (read source during VERIFY)
    output logic        clk_en_override, // drives codeStorage clk_en
    output logic        ctrRst,          // resets codeStorage counter
    output logic        srst_lv,         // holds lock_validation in reset during ENTRY
    output logic        cp_complete,     // verification passed → wrapper swaps address pointer
    output logic        cp_fail          // mismatch or cancel → supervisor_requests → NO_REQUEST
);
```

`inactive_addr` is derived inside the module: `inactive_addr = active_addr ^ 6'b010000`.

---

## Address Swap Registers (access_permission_wrapper.sv)

Two 1-bit flip-flops track which region is currently active for each identity:

```sv
logic user_active, super_active; // 0 = region A, 1 = region B; init 0 on resetN
```

On `cp_complete`, the wrapper flips the relevant bit:

```sv
always_ff @(posedge clk, negedge resetN) begin
    if (!resetN) begin
        user_active  <= 1'b0;
        super_active <= 1'b0;
    end else if (cp_complete) begin
        if (is_supervisor) super_active <= ~super_active;
        else               user_active  <= ~user_active;
    end
end
```

`rStartingAddress` changes from a hardcoded wire to register-driven:

```sv
// was: assign rStartingAddress = key ? 6'b100000 : 6'b000000;
assign rStartingAddress = {key, key ? super_active : user_active, 4'b0000};
```

`is_supervisor` is driven from `lab_2.sv` — it is the latched value of `change_super_req` at the moment `cp_start` was issued.

---

## Cancel Path

Supervisor enters `1010` as the first digit during ENTRY → only the terminator is written to the inactive region. VERIFY receives a re-entry that cannot match (any real digit sequence vs a single terminator) → `lv_error` → `cp_fail` → `supervisor_requests` returns to `NO_REQUEST`. The active region is never touched.

---

## Signal State Table

| State | wren | wStartAddr | rStartAddr | clk_en_override | srst_lv | dataIn |
|---|---|---|---|---|---|---|
| ENTRY_RST | 0 | inactive | — | 0 | 1 | — |
| ENTRY | 1 | inactive | — | enter_d | 1 | switches |
| VERIFY_RST | 0 | — | inactive | 0 | 1 | — |
| VERIFY_WAIT | 0 | — | inactive | 0 | 0 | — |
| VERIFY | 0 | — | inactive | enter_d | 0 | — |
| DONE/ERROR | 0 | — | — | 0 | 0 | — |
