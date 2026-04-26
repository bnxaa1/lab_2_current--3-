`timescale 1ns / 1ps

// Testbench: tb_access_permission_wrapper
//
// RAM (ramm.mif) — regions used by this DUT:
//   User       region (key=0, rStartingAddress=0):
//     addr 0-4 : 1, 2, 3, 4, 10   (10 = 4'b1010 end marker)
//     Correct sequence: 1, 2, 3, 4, 1010
//
//   Supervisor region (key=1, rStartingAddress=20):
//     addr 20-24: 2, 0, 2, 6, 10  (10 = 4'b1010 end marker at addr 24)
//     Correct sequence: 2, 0, 2, 6, 1010  (5 presses)
//
// Clock: 1 kHz (clk1ms) — clock1 is in top level; testbench drives clk directly.
// Debounce (one_pulse_generator): 15 clk cycles → PRESS/RELEASE = 20 cycles.
//
// enter_access = enter_d  (no start signal; first press is the first digit)
// S0 does not assert rst_lv; all transitions back to S0 assert rst_lv.
// srst_access resets AP FSM + all submodules via effective_rst_lv in wrapper.
// Timeout counter resets to 0 on S0→S1 (user auth start only; no timeout for supervisor).

module tb_access_permission_wrapper;

    // ── DUT ports ────────────────────────────────────────────────────────────
    logic        resetN, srst_access, key_raw, key_to_dut, enter_al, clk;
    logic        rst_failureCtr, wren;
    logic [3:0]  switches, dataIn;
    logic        Err_LED, rst_lv, Corr_LED, increment, timeOut, locked;
    logic        correct, error;
    logic [2:0]  state_p;

    // ── Event flags (latch posedge pulses; cleared via clear_ev before each test) ──
    logic ev_correct, ev_error, ev_Corr_LED, ev_Err_LED;

    access_permission_wrapper dut (
        .resetN      (resetN),
        .srst_access (srst_access),
        .key         (key_to_dut),
        .enter_al    (enter_al),
        .switches    (switches),
        .clk         (clk),
        .rst_failureCtr (rst_failureCtr),
        .wren        (wren),
        .dataIn      (dataIn),
        .Err_LED     (Err_LED),
        .rst_lv      (rst_lv),
        .Corr_LED    (Corr_LED),
        .increment   (increment),
        .timeOut     (timeOut),
        .locked      (locked),
        .correct     (correct),
        .error       (error),
        .state_p     (state_p)
    );

    // ── 1 kHz clock ──────────────────────────────────────────────────────────
    localparam CLK_HALF_NS    = 500_000;   // 500 µs → 1 ms period
    localparam PRESS_CYCLES   = 20;        // > 15-cycle debounce window
    localparam RELEASE_CYCLES = 20;

    // key_raw is the testbench-requested key value.
    // key_to_dut is the actual DUT key input.
    // Once locked=1, the supervisor key is forced high continuously.
    assign key_to_dut = locked ? 1'b1 : key_raw;

    initial clk = 0;
    always #CLK_HALF_NS clk = ~clk;

    // ── Task: hard reset ─────────────────────────────────────────────────────
    // Async-resets AP FSM, lock_validation FSM, codeStorage counter via resetN.
    // Also pulses rst_failureCtr to clear ThreeBitsCounter (no aclr port on IP).
    task apply_reset;
    begin
        resetN         = 1'b0;
        srst_access    = 1'b0;
        key_raw        = 1'b0;
        enter_al       = 1'b1;   // idle: active-low not pressed
        switches       = 4'd0;
        rst_failureCtr = 1'b0;
        wren           = 1'b0;
        dataIn         = 4'd0;
        repeat (3) @(posedge clk);
        resetN         = 1'b1;
        rst_failureCtr = 1'b1;   // clear failure counter; no aclr on ThreeBitsCounter IP
        repeat (2) @(posedge clk);
        rst_failureCtr = 1'b0;
        repeat (3) @(posedge clk);
    end
    endtask

    // ── Task: synchronous reset via srst_access ───────────────────────────────
    // srst_access resets AP FSM to S0 AND propagates through effective_rst_lv
    // to reset lock_validation FSM + codeStorage counter (all submodules under access_permission_wrapper).
    // Does NOT reset ThreeBitsCounter — use apply_reset when locked state must be cleared.
    task sync_reset;
    begin
        srst_access = 1'b1;
        repeat (2) @(posedge clk); #1;
        srst_access = 1'b0;
        repeat (5) @(posedge clk);   // settle
    end
    endtask

    // ── Task: clear event flags ───────────────────────────────────────────────
    // Call before entering digits for each test so captured edges don't bleed across tests.
    task clear_ev;
    begin
        ev_correct  = 1'b0;
        ev_error    = 1'b0;
        ev_Corr_LED = 1'b0;
        ev_Err_LED  = 1'b0;
    end
    endtask

    // ── Task: enter one debounced digit ──────────────────────────────────────
    task enter_digit;
        input [3:0] digit;
    begin
        switches = digit;
        @(negedge clk);
        enter_al = 1'b0;
        repeat (PRESS_CYCLES)    @(posedge clk);
        enter_al = 1'b1;
        repeat (RELEASE_CYCLES)  @(posedge clk);
    end
    endtask

    // ── Task: enter one supervisor digit ────────────────────────────────────
    // Forces requested key=1 before, during, and after the button press so access_permission
    // stays in S2 for the entire supervisor authentication sequence.
    task enter_supervisor_digit;
        input [3:0] digit;
    begin
        key_raw = 1'b1;
        switches = digit;
        @(negedge clk);
        key_raw = 1'b1;
        enter_al = 1'b0;
        repeat (PRESS_CYCLES) begin
            @(posedge clk);
            key_raw = 1'b1;
        end
        enter_al = 1'b1;
        repeat (RELEASE_CYCLES) begin
            @(posedge clk);
            key_raw = 1'b1;
        end
    end
    endtask

    // ── Monitors ─────────────────────────────────────────────────────────────
    always @(posedge correct)  begin ev_correct  = 1'b1; $display("[%0t ns]  >> CORRECT   (state_p=%0d)", $time, state_p); end
    always @(posedge error)    begin ev_error    = 1'b1; $display("[%0t ns]  >> ERROR     (state_p=%0d)", $time, state_p); end
    always @(posedge Corr_LED) begin ev_Corr_LED = 1'b1; $display("[%0t ns]  >> Corr_LED ON", $time); end
    always @(posedge Err_LED)  begin ev_Err_LED  = 1'b1; $display("[%0t ns]  >> Err_LED  ON", $time); end
    always @(posedge locked) $display("[%0t ns]  >> LOCKED asserted; DUT key forced high", $time);
    always @(posedge timeOut)  $display("[%0t ns]  >> TIMEOUT fired", $time);

    // Safety invariant: once locked=1, the DUT must always see key=1.
    always @(posedge clk)
        if (locked && !key_to_dut)
            $error("[%0t ns] key_to_dut dropped while locked", $time);

    // ── Test sequence ─────────────────────────────────────────────────────────
    initial begin
        ev_correct = 0; ev_error = 0; ev_Corr_LED = 0; ev_Err_LED = 0;
        $display("=== tb_access_permission_wrapper ===");
        apply_reset;
        $display("[%0t ns] Reset done", $time);

        // ── Test 1: correct user password ─────────────────────────────────
        $display("[%0t ns] Test 1: correct user password  1-2-3-4-1010", $time);
        clear_ev;
        enter_digit(4'd1);
        enter_digit(4'd2);
        enter_digit(4'd3);
        enter_digit(4'd4);
        enter_digit(4'b1010);
        repeat (4) @(posedge clk);
        if (ev_correct && ev_Corr_LED)
            $display("[%0t ns] Test 1 PASS", $time);
        else
            $display("[%0t ns] Test 1 FAIL  ev_correct=%b ev_Corr_LED=%b", $time, ev_correct, ev_Corr_LED);
        sync_reset;

        // ── Test 2: wrong first digit ──────────────────────────────────────
        $display("[%0t ns] Test 2: wrong first digit  9-1010", $time);
        clear_ev;
        enter_digit(4'd9);          // expected 1
        enter_digit(4'b1010);
        repeat (4) @(posedge clk);
        if (ev_error && ev_Err_LED)
            $display("[%0t ns] Test 2 PASS", $time);
        else
            $display("[%0t ns] Test 2 FAIL  ev_error=%b ev_Err_LED=%b", $time, ev_error, ev_Err_LED);
        apply_reset;                // clears failure counter; test 2 increments it

        // ── Test 3: correct digits, wrong at end-marker position ───────────
        // At digit 5, code = 4'b1010 (end marker); entering 9 instead → mismatch
        $display("[%0t ns] Test 3: correct 1-2-3-4, wrong end-marker  1-2-3-4-9-1010", $time);
        clear_ev;
        enter_digit(4'd1);
        enter_digit(4'd2);
        enter_digit(4'd3);
        enter_digit(4'd4);
        enter_digit(4'd9);          // code=1010, switches=9 → mismatch
        enter_digit(4'b1010);       // terminate while in mismatch → error
        repeat (4) @(posedge clk);
        if (ev_error)
            $display("[%0t ns] Test 3 PASS", $time);
        else
            $display("[%0t ns] Test 3 FAIL", $time);
        apply_reset;                // clears failure counter; test 3 increments it

        // ── Test 4: early end marker (1010 as first digit) ─────────────────
        $display("[%0t ns] Test 4: early end marker  1010 at digit 0", $time);
        clear_ev;
        enter_digit(4'b1010);
        repeat (4) @(posedge clk);
        if (ev_error)
            $display("[%0t ns] Test 4 PASS", $time);
        else
            $display("[%0t ns] Test 4 FAIL", $time);
        apply_reset;                // clears failure counter; test 4 increments it

        // ── Test 5: one digit correct, one digit wrong ─────────────────────
        $display("[%0t ns] Test 5: first digit correct, second wrong  1-9-1010", $time);
        clear_ev;
        enter_digit(4'd1);          // code[0]=1 ✓
        enter_digit(4'd9);          // code[1]=2, 9≠2 → mismatch
        enter_digit(4'b1010);
        repeat (4) @(posedge clk);
        if (ev_error)
            $display("[%0t ns] Test 5 PASS", $time);
        else
            $display("[%0t ns] Test 5 FAIL", $time);
        apply_reset;                // clears failure counter; test 5 increments it

        // ── Test 6: key pressed during user auth → interrupt ───────────────
        // access_permission S1: key=1 → rst_lv=1, back to S0; then correct sequence works
        $display("[%0t ns] Test 6: supervisor key interrupt during user auth", $time);
        clear_ev;
        enter_digit(4'd1);
        enter_digit(4'd2);          // partway through user entry
        key_raw = 1'b1;             // supervisor inserts key
        repeat (3) @(posedge clk);  // access_permission sees key=1 in S1 → rst_lv, S0
        key_raw = 1'b0;
        repeat (3) @(posedge clk);  // settle back at S0
        clear_ev;                   // discard any partial-entry events; test only cares about recovery
        enter_digit(4'd1);
        enter_digit(4'd2);
        enter_digit(4'd3);
        enter_digit(4'd4);
        enter_digit(4'b1010);
        repeat (4) @(posedge clk);
        if (ev_correct)
            $display("[%0t ns] Test 6 PASS  (recovered after key interrupt)", $time);
        else
            $display("[%0t ns] Test 6 FAIL  ev_correct=%b after key interrupt recovery", $time, ev_correct);
        sync_reset;

        // ── Test 7: key removed during supervisor auth → interrupt ─────────
        // access_permission S2: !key → rst_lv=1, back to S0; then user can authenticate
        $display("[%0t ns] Test 7: supervisor removes key during supervisor auth", $time);
        clear_ev;
        key_raw = 1'b1;
        repeat (3) @(posedge clk);  // supervisor inserts key; rStartingAddress → 20
        enter_digit(4'd2);          // S0→S2; code[20]=2, digit=2 matches so far
        key_raw = 1'b0;             // supervisor removes key mid-auth → rst_lv, S0
        repeat (3) @(posedge clk);
        clear_ev;                   // discard any partial-entry events
        enter_digit(4'd1);
        enter_digit(4'd2);
        enter_digit(4'd3);
        enter_digit(4'd4);
        enter_digit(4'b1010);
        repeat (4) @(posedge clk);
        if (ev_correct)
            $display("[%0t ns] Test 7 PASS  (recovered after supervisor key removal)", $time);
        else
            $display("[%0t ns] Test 7 FAIL  ev_correct=%b", $time, ev_correct);
        sync_reset;

        // ── Test 8: srst_access mid-entry, then correct sequence ───────────
        // srst_access now resets AP FSM + codeStorage counter + lock_validation FSM
        // via effective_rst_lv in wrapper; counter is 0 after sync_reset regardless
        // of how many digits were entered before it.
        $display("[%0t ns] Test 8: srst_access mid-entry, then correct sequence", $time);
        clear_ev;
        enter_digit(4'd1);
        enter_digit(4'd2);
        sync_reset;                 // resets all submodules; counter back to 0
        clear_ev;                   // discard partial-entry events before clean run
        enter_digit(4'd1);
        enter_digit(4'd2);
        enter_digit(4'd3);
        enter_digit(4'd4);
        enter_digit(4'b1010);
        repeat (4) @(posedge clk);
        if (ev_correct)
            $display("[%0t ns] Test 8 PASS", $time);
        else
            $display("[%0t ns] Test 8 FAIL", $time);
        sync_reset;

        // ── Test 9: 4 wrong attempts → locked ──────────────────────────────
        // Each wrong attempt: enter_d → S0→S1, wrong digit → lock_validation mismatch,
        // 1010 → error=1, access_permission S1→S5 (increment=1, rst_lv=1) → S0.
        // After 4 increments: ThreeBitsCounter=4 → locked=1.
        $display("[%0t ns] Test 9: 4 wrong attempts → locked", $time);
        repeat (4) begin : wrong_attempts
            enter_digit(4'd9);      // wrong digit (expected 1)
            enter_digit(4'b1010);
            repeat (10) @(posedge clk); // wait for S5→S0 auto-recovery
        end
        repeat (4) @(posedge clk);
        if (locked)
            $display("[%0t ns] Test 9 PASS  (locked after 4 failures)", $time);
        else
            $display("[%0t ns] Test 9 FAIL  locked=%b increment count may not have reached 4", $time, locked);

        // Test 9b: once locked=1, keep supervisor key inserted and authenticate.
        // key must remain 1 for the whole S2 supervisor authentication sequence;
        // otherwise access_permission exits S2 back to S0.
        key_raw = 1'b1;
        repeat (3) @(posedge clk);
        clear_ev;
        key_raw = 1'b1;
        repeat (3) @(posedge clk);
        enter_supervisor_digit(4'd2);
        enter_supervisor_digit(4'd0);
        enter_supervisor_digit(4'd2);
        enter_supervisor_digit(4'd6);
        enter_supervisor_digit(4'b1010);
        repeat (4) @(posedge clk);
        if (ev_correct && state_p == 3'd4)
            $display("[%0t ns] Test 9b PASS  (supervisor authenticated while locked, state_p=%0d S4)", $time, state_p);
        else
            $display("[%0t ns] Test 9b FAIL  ev_correct=%b state_p=%0d expected supervisor auth to S4", $time, ev_correct, state_p);
        apply_reset;                // full reset: clears locked + all submodules

        // ── Test 10: timeout during user auth ──────────────────────────────
        // Timeout counter resets to 0 on S0→S1 transition (first digit press),
        // giving the full 5 s window from that point. After 5000 cycles in S1
        // with no further input, timeOut fires → access_permission S1→S0.
        // WARNING: this test runs ~5100 cycles at 1 kHz = 5.1 s of simulation.
        $display("[%0t ns] Test 10: timeout (5100 cycles after entering S1)", $time);
        enter_digit(4'd1);          // S0→S1; rst_timeoutCtr fires → counter starts from 0
        repeat (5100) @(posedge clk);
        if (state_p == 3'd0)
            $display("[%0t ns] Test 10 PASS  (returned to S0 after timeout)", $time);
        else
            $display("[%0t ns] Test 10 FAIL  state_p=%0d  expected 0", $time, state_p);
        sync_reset;

        // ── Test 11: locked system still accepts supervisor auth → S4 ───────
        // Lock system first (4 failures), then supervisor inserts key and authenticates.
        // Keep key=1 for the full supervisor password entry; otherwise S2 sees !key
        // and exits back to S0 before authentication can complete.
        $display("[%0t ns] Test 11: locked system accepts supervisor auth → S4", $time);
        repeat (4) begin : lock_sys
            enter_digit(4'd9);
            enter_digit(4'b1010);
            repeat (10) @(posedge clk);
        end
        repeat (4) @(posedge clk);
        if (!locked) $display("[%0t ns] Test 11 setup FAIL: system not locked", $time);
        key_raw = 1'b1;
        repeat (3) @(posedge clk);
        clear_ev;
        key_raw = 1'b1;
        repeat (3) @(posedge clk);
        enter_supervisor_digit(4'd2);
        enter_supervisor_digit(4'd0);
        enter_supervisor_digit(4'd2);
        enter_supervisor_digit(4'd6);
        enter_supervisor_digit(4'b1010);
        repeat (4) @(posedge clk);
        if (ev_correct && state_p == 3'd4)
            $display("[%0t ns] Test 11 PASS  (supervisor authenticated while locked, state_p=%0d S4)", $time, state_p);
        else
            $display("[%0t ns] Test 11 FAIL  ev_correct=%b state_p=%0d  expected ev_correct=1 S4", $time, ev_correct, state_p);
        apply_reset;

        $display("=== simulation complete ===");
        $stop;
    end

endmodule
