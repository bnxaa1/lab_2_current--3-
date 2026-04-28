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
IDLE → ENTRY → VERIFY → DONE / ERROR
```

The original design had intermediate `ENTRY_RST`, `VERIFY_RST`, `VERIFY_WAIT`, and `COPY` states. All of these were removed:

- `ENTRY_RST` / `VERIFY_RST` — counter and FSM resets are now **Mealy outputs** on the IDLE→ENTRY and ENTRY→VERIFY transitions (asserted combinatorially on the same clock edge as the state change).
- `VERIFY_WAIT` — eliminated; the 1-cycle RAM read latency is absorbed by `lock_validation`'s debounce window (15 cycles) before `enter_d` fires.
- `COPY_PREP` / `COPY_WAIT1` / `COPY_WAIT2` / `COPY` — eliminated entirely; the address-swap eliminates the need to copy digits from the inactive to the active region.

| State | Action |
|---|---|
| IDLE | `cp_active=0`; wait for `start` pulse. On `start` (Mealy): assert `ctrRst`, `srst_lv`; go to ENTRY |
| ENTRY | `cp_active=1`, `srst_lv=1`, `wren=1`, `dataIn=switches`; on `enter_d`: `clk_en_override=1`; if `switches==4'hD` or `done` (Mealy): assert `ctrRst`, `srst_lv`; go to VERIFY |
| VERIFY | `cp_active=1`; on `enter_d`: `clk_en_override=1`; if `lv_correct` → DONE; if `lv_error` → ERROR |
| DONE | Assert `cp_complete` for 1 cycle → IDLE |
| ERROR | Assert `cp_fail` for 1 cycle → IDLE |

---

## Ports

```sv
module change_password (
    input  logic        clk, resetN,
    input  logic        start,           // level signal from supervisor_requests (high while command active)
    input  logic        enter_d,         // debounced keypress from lock_validation_wrapper
    input  logic        done,            // codeStorage counter at 9 (max digits reached)
    input  logic        lv_correct,      // lock_validation correct output
    input  logic        lv_error,        // lock_validation error output
    input  logic [3:0]  switches,        // digit input
    input  logic [5:0]  active_addr,     // current active region start address from wrapper
    output logic        cp_active,       // 1 while running; mux selector in access_permission_wrapper
    output logic        wren,            // RAM write enable
    output logic        clk_en_override, // drives codeStorage clk_en (redundant; left unconnected in lab_2)
    output logic        ctrRst,          // resets codeStorage counter
    output logic        srst_lv,         // holds lock_validation in reset during ENTRY
    output logic        cp_complete,     // verification passed → wrapper swaps address pointer
    output logic        cp_fail,         // mismatch → supervisor_requests → NO_REQUEST
    output logic [3:0]  dataIn,          // write data to inactive region
    output logic [5:0]  target_addr      // inactive region address; used by wrapper for both rStartingAddress and wStartingAddress
);
```

`target_addr` is derived inside the module: `target_addr = active_addr ^ 6'b010000`.

`clk_en_override` is present but left unconnected in `lab_2.sv` — `enter_d` already drives `codeStorage.clk_en` through the normal path.

---

## Address Swap Registers (access_permission_wrapper.sv)

Two 1-bit flip-flops track which region is currently active for each identity:

```sv
logic user_active, super_active; // 0 = region A, 1 = region B
```

These registers have **no reset** — they survive a `resetN` restart so that a password change is not lost on power cycle. They only change on `cp_complete`:

```sv
always_ff @(posedge clk) begin  // no negedge resetN — survives restart
    if (cp_complete) begin
        if (is_supervisor) super_active <= ~super_active;
        else               user_active  <= ~user_active;
    end
end
```

`rStartingAddress` is register-driven:

```sv
assign normal_rAddr     = {key, key ? super_active : user_active, 4'b0000};
assign active_addr      = normal_rAddr;
assign rStartingAddress = cp_active ? target_addr : normal_rAddr;
```

`is_supervisor` in `lab_2.sv` is `assign is_supervisor = change_super_req` — stable throughout the change_password session.

---

## Cancel Path

If the supervisor presses `D` as the first digit during ENTRY, only the terminator is written to the inactive region. VERIFY receives a re-entry that cannot match (any real digit sequence vs. a single terminator) → `lv_error` → `cp_fail` → `supervisor_requests` returns to `NO_REQUEST`. The active region is never touched.

---

## Signal State Table

| State | cp_active | wren | dataIn | clk_en_override | ctrRst | srst_lv |
|---|---|---|---|---|---|---|
| IDLE (idle) | 0 | 0 | 0 | 0 | 0 | 0 |
| IDLE → ENTRY (Mealy on start) | 0 | 0 | 0 | 0 | 1 | 1 |
| ENTRY | 1 | 1 | switches | enter_d | 0 | 1 |
| ENTRY → VERIFY (Mealy on terminator/done) | 1 | 1 | switches | 1 | 1 | 1 |
| VERIFY | 1 | 0 | 0 | enter_d | 0 | 0 |
| DONE | 1 | 0 | 0 | 0 | 0 | 0 |
| ERROR | 1 | 0 | 0 | 0 | 0 | 0 |
