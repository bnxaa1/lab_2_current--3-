`timescale 1ns/1ps

// =============================================================================
// tb_lab_2.sv — full-system testbench for lab_2
//
// Bypasses keypad GPIO matrix scanning by forcing uut.switches / uut.enter_al
// directly, which drives the same internal nets consumed by lock_validation /
// one_pulse_generator / access_permission_wrapper unchanged.
// Weak pull-ups on cols/rows keep keypad_interface in S_IDLE throughout.
//
// Test list:
//   T1  Correct user password         → correct + Corr_LED
//   T2  Wrong user password           → error + Err_LED
//   T3  Early terminator              → error
//   T4  4 failures                    → system locked; user auth blocked
//   T5  Supervisor unlock             → failure counter cleared (continues T4)
//   T6  Timeout during user auth      → back to S0 (waits 5100 clk1ms cycles)
//   T7  Key insert mid-entry          → user auth aborted to S0
//   T8  Key removal mid supervisor    → supervisor auth aborted to S0
//   T9  srst_access mid-entry         → back to S0
//   T10 Supervisor auth (unlocked)    → S3 session_active
//   T11 Change user password (pass)   → cp_complete; new pass accepted
//   T12 Change user password (fail)   → cp_fail; supervisor session preserved
//   T13 Change supervisor password    → cp_complete
// =============================================================================

module tb_lab_2;

    // ─── DUT ports ────────────────────────────────────────────────────────────
    logic       key, clk, resetN, srst_access, enter_al;
    logic [3:0] switches;
    logic       error, correct, Err_LED, Corr_LED, Lock_LED;

    lab_2 uut (
        .key         (key),
        .clk         (clk),
        .resetN      (resetN),
        .srst_access (srst_access),
        .enter_al    (enter_al),
        .switches    (switches),
        .error       (error),
        .correct     (correct),
        .Err_LED     (Err_LED),
        .Corr_LED    (Corr_LED),
        .Lock_LED    (Lock_LED)
    );

    // 50 MHz system clock
    initial clk = 0;
    always #10 clk = ~clk;

    // ─── Edge-capture flags ───────────────────────────────────────────────────
    // Latch 1-cycle pulses so checks don't need sub-cycle timing
    logic ev_correct, ev_error, ev_Corr_LED, ev_Err_LED;
    always @(posedge correct)  ev_correct  = 1'b1;
    always @(posedge error)    ev_error    = 1'b1;
    always @(posedge Corr_LED) ev_Corr_LED = 1'b1;
    always @(posedge Err_LED)  ev_Err_LED  = 1'b1;

    task automatic clear_ev;
        ev_correct  = 1'b0;
        ev_error    = 1'b0;
        ev_Corr_LED = 1'b0;
        ev_Err_LED  = 1'b0;
    endtask

    // ─── Check helpers ────────────────────────────────────────────────────────
    int test_num, check_count, fail_count;

    task automatic check1(input string lbl, input logic got, input logic exp);
        check_count++;
        if (got === exp)
            $display("  PASS [T%0d] @%0t  %s", test_num, $time, lbl);
        else begin
            $display("  FAIL [T%0d] @%0t  %s   got=%0b  exp=%0b", test_num, $time, lbl, got, exp);
            fail_count++;
        end
    endtask

    task automatic check3(input string lbl, input logic [2:0] got, input logic [2:0] exp);
        check_count++;
        if (got === exp)
            $display("  PASS [T%0d] @%0t  %s", test_num, $time, lbl);
        else begin
            $display("  FAIL [T%0d] @%0t  %s   got=%0d  exp=%0d", test_num, $time, lbl, got, exp);
            fail_count++;
        end
    endtask

    // ─── Reset ───────────────────────────────────────────────────────────────
    task automatic apply_reset;
        key    = 1'b0;
        resetN = 1'b0;
        repeat(4) @(posedge uut.clk1ms);
        resetN = 1'b1;
        repeat(2) @(posedge uut.clk1ms);
        clear_ev;
    endtask

    // ─── Key press ───────────────────────────────────────────────────────────
    // Drives decoded keypad inputs directly so one_pulse_generator generates enter_d.
    // Timing budget (clk1ms cycles):
    //   hold=20: enter_d fires at cycle 16 (S1×15 + S2×1); 20 > 16 ✓
    //   release=25: OPG S3→S4(15 cycles)→S0 takes ~17 more cycles after enter_al rises;
    //              total OPG cycle ≈ 37; 20+25=45 > 37 so S0 is reached before next press ✓
    task press_key(input logic [3:0] digit);
        switches = digit;
        enter_al = 1'b0;
        repeat(20) @(posedge uut.clk1ms);
        enter_al = 1'b1;
        repeat(25) @(posedge uut.clk1ms);
    endtask

    // Default passwords (from ramm.mif)
    //   User  A : 1,2,3,4,13   (addr 0–4,  13=4'hD terminator)
    //   Super A : 2,0,2,6,13   (addr 32–36, 13=4'hD terminator)
    task automatic enter_user_pass;
        press_key(4'd1); press_key(4'd2); press_key(4'd3);
        press_key(4'd4); press_key(4'd13);
    endtask

    task automatic enter_super_pass;
        press_key(4'd2); press_key(4'd0); press_key(4'd2);
        press_key(4'd6); press_key(4'd13);
    endtask

    // =========================================================================
    // MAIN TEST SEQUENCE
    // =========================================================================
    initial begin
        key = 0; resetN = 1; srst_access = 0; enter_al = 1'b1; switches = 4'd0;
        test_num = 0; check_count = 0; fail_count = 0;
        clear_ev;
        apply_reset;

        // ── T1: Correct user password ─────────────────────────────────────────
        test_num = 1;
        $display("\n[T1] Correct user password → correct + Corr_LED");
        enter_user_pass;
        repeat(5) @(posedge uut.clk1ms);
        check1("correct fired",  ev_correct,  1'b1);
        check1("error silent",   ev_error,    1'b0);
        check1("Corr_LED fired", ev_Corr_LED, 1'b1);
        check1("Err_LED silent", ev_Err_LED,  1'b0);
        apply_reset;

        // ── T2: Wrong user password ───────────────────────────────────────────
        test_num = 2;
        $display("\n[T2] Wrong user password → error + Err_LED");
        press_key(4'd9); press_key(4'd9); press_key(4'd9);
        press_key(4'd9); press_key(4'd13);
        repeat(5) @(posedge uut.clk1ms);
        check1("error fired",     ev_error,    1'b1);
        check1("correct silent",  ev_correct,  1'b0);
        check1("Err_LED fired",   ev_Err_LED,  1'b1);
        check1("Corr_LED silent", ev_Corr_LED, 1'b0);
        apply_reset;

        // ── T3: Early terminator ──────────────────────────────────────────────
        test_num = 3;
        $display("\n[T3] Early terminator (only 1 digit) → error");
        press_key(4'd1); press_key(4'd13);
        repeat(5) @(posedge uut.clk1ms);
        check1("error fired",    ev_error,   1'b1);
        check1("correct silent", ev_correct, 1'b0);
        apply_reset;

        // ── T4: 4 failures → system locked ───────────────────────────────────
        test_num = 4;
        $display("\n[T4] 4 wrong attempts → locked; further user auth blocked");
        repeat(4) begin
            press_key(4'd9); press_key(4'd13);
            repeat(5) @(posedge uut.clk1ms);
        end
        check1("locked asserted", uut.locked, 1'b1);
        check1("Lock_LED asserted while locked", Lock_LED, 1'b1);
        clear_ev;
        enter_user_pass;
        repeat(5) @(posedge uut.clk1ms);
        check1("correct blocked while locked", ev_correct, 1'b0);
        // leave locked — T5 continues from this state

        // ── T5: Supervisor unlock (system still locked from T4) ───────────────
        test_num = 5;
        $display("\n[T5] Supervisor unlocks locked system");
        key = 1'b1;
        repeat(2) @(posedge uut.clk1ms);
        enter_super_pass;
        repeat(3) @(posedge uut.clk1ms);
        check1("session_active asserted", uut.session_active, 1'b1);
        check3("AP FSM in S3",            uut.access_state_p, 3'd3);
        clear_ev;
        press_key(4'd3); // '3' → UNLOCK_REQUEST → failure counter cleared
        repeat(5) @(posedge uut.clk1ms);
        check1("system unlocked",         uut.locked,         1'b0);
        check1("Corr_LED on unlock",      ev_Corr_LED,        1'b1);
        press_key(4'd2); // '2' → EXIT_REQUEST → srst_access → S0
        repeat(5) @(posedge uut.clk1ms);
        check1("session ended after exit", uut.session_active, 1'b0);
        key = 1'b0;
        apply_reset;

        // ── T6: Timeout during user auth ──────────────────────────────────────
        // NOTE: waits 5 100 clk1ms cycles (~5.1 s sim time) to exceed 5 000-cycle threshold
        test_num = 6;
        $display("\n[T6] Timeout during user auth → back to S0 (long sim wait)");
        press_key(4'd1); // first digit: S0 → S1, timeout counter starts
        repeat(5100) @(posedge uut.clk1ms);
        check1("no correct after timeout",     ev_correct,         1'b0);
        check1("no error after timeout",       ev_error,           1'b0);
        check1("Err_LED slow blink on timeout", ev_Err_LED,        1'b1);
        check3("AP back to S0",                uut.access_state_p, 3'd0);
        apply_reset;

        // ── T7: Key insert aborts user auth ───────────────────────────────────
        test_num = 7;
        $display("\n[T7] Supervisor key inserted mid user-auth → abort to S0");
        press_key(4'd1); press_key(4'd2);
        key = 1'b1;
        repeat(3) @(posedge uut.clk1ms);
        check3("AP aborted to S0 on key insert", uut.access_state_p, 3'd0);
        key = 1'b0;
        apply_reset;

        // ── T8: Key removal aborts supervisor auth ────────────────────────────
        test_num = 8;
        $display("\n[T8] Supervisor key removed mid supervisor-auth → abort to S0");
        key = 1'b1;
        repeat(2) @(posedge uut.clk1ms);
        press_key(4'd2); press_key(4'd0);
        key = 1'b0; // remove key before password complete
        repeat(3) @(posedge uut.clk1ms);
        check3("AP aborted to S0 on key removal", uut.access_state_p, 3'd0);
        apply_reset;

        // ── T9: srst_access mid-entry ─────────────────────────────────────────
        test_num = 9;
        $display("\n[T9] srst_access during user auth → back to S0");
        press_key(4'd1); press_key(4'd2);
        @(posedge uut.clk1ms);
        srst_access = 1'b1;
        @(posedge uut.clk1ms);
        srst_access = 1'b0;
        repeat(2) @(posedge uut.clk1ms);
        check3("back to S0 after srst_access", uut.access_state_p, 3'd0);
        apply_reset;

        // ── T10: Supervisor auth while unlocked ───────────────────────────────
        test_num = 10;
        $display("\n[T10] Supervisor auth while unlocked → S3 session_active");
        key = 1'b1;
        repeat(2) @(posedge uut.clk1ms);
        enter_super_pass;
        repeat(3) @(posedge uut.clk1ms);
        check1("session_active",              uut.session_active, 1'b1);
        check3("AP FSM in S3",               uut.access_state_p, 3'd3);
        check1("correct fired",              ev_correct,         1'b1);
        check1("Corr_LED on supervisor auth", ev_Corr_LED,       1'b1);
        press_key(4'd2); // exit
        repeat(3) @(posedge uut.clk1ms);
        key = 1'b0;
        apply_reset;

        // ── T11: Change user password — success ───────────────────────────────
        test_num = 11;
        $display("\n[T11] Change user password — success path");
        key = 1'b1;
        repeat(2) @(posedge uut.clk1ms);
        enter_super_pass; // authenticate supervisor → S3
        repeat(2) @(posedge uut.clk1ms);
        press_key(4'd1); // '1' → CHANGE_USER_PASSWORD → change_password IDLE→ENTRY
        repeat(3) @(posedge uut.clk1ms);
        check1("cp_active after command", uut.cp_active, 1'b1);
        // ENTRY: write new password 5,6,7,8,D (4'hD=13) to inactive region (addr 16–20)
        press_key(4'd5); press_key(4'd6); press_key(4'd7);
        press_key(4'd8); press_key(4'd13);
        repeat(3) @(posedge uut.clk1ms);
        // VERIFY: re-enter same password; lock_validation reads from inactive region
        clear_ev;
        press_key(4'd5); press_key(4'd6); press_key(4'd7);
        press_key(4'd8); press_key(4'd13);
        repeat(5) @(posedge uut.clk1ms);
        check1("verify correct (new pass matches)", ev_correct,    1'b1);
        check1("cp_active cleared after DONE",      uut.cp_active, 1'b0);
        // exit supervisor session; user_active=1 remains (no reset yet)
        press_key(4'd2);
        repeat(5) @(posedge uut.clk1ms);
        key = 1'b0;
        // verify new password works before reset (user_active=1 → region B active)
        clear_ev;
        press_key(4'd5); press_key(4'd6); press_key(4'd7);
        press_key(4'd8); press_key(4'd13);
        repeat(5) @(posedge uut.clk1ms);
        check1("new user password accepted", ev_correct, 1'b1);
        apply_reset; // resetN resets FSM state only; user_active persists (region B still active)

        // ── T12: Change user password — wrong verify ──────────────────────────
        test_num = 12;
        $display("\n[T12] Change user password — wrong verify → cp_fail");
        key = 1'b1;
        repeat(2) @(posedge uut.clk1ms);
        enter_super_pass;
        repeat(2) @(posedge uut.clk1ms);
        press_key(4'd1); // CHANGE_USER_PASSWORD
        repeat(3) @(posedge uut.clk1ms);
        // ENTRY: new password 3,3,3,3,D (4'hD=13)
        press_key(4'd3); press_key(4'd3); press_key(4'd3);
        press_key(4'd3); press_key(4'd13);
        repeat(3) @(posedge uut.clk1ms);
        // VERIFY: different password → lock_validation fires error → ERROR→IDLE
        press_key(4'd9); press_key(4'd9); press_key(4'd9);
        press_key(4'd9); press_key(4'd13);
        repeat(5) @(posedge uut.clk1ms);
        check1("cp_fail: cp_active cleared",        uut.cp_active,      1'b0);
        check1("supervisor session still active",   uut.session_active, 1'b1);
        press_key(4'd2); // exit
        repeat(3) @(posedge uut.clk1ms);
        key = 1'b0;
        apply_reset;

        // ── T13: Change supervisor password — success ─────────────────────────
        test_num = 13;
        $display("\n[T13] Change supervisor password — success path");
        key = 1'b1;
        repeat(2) @(posedge uut.clk1ms);
        enter_super_pass;
        repeat(2) @(posedge uut.clk1ms);
        press_key(4'd4); // '4' → CHANGE_SUPERVISOR_PASSWORD
        repeat(3) @(posedge uut.clk1ms);
        check1("cp_active high (super change)", uut.cp_active, 1'b1);
        // ENTRY: new supervisor password 1,1,1,1,D (4'hD=13) to inactive super region (addr 48–52)
        press_key(4'd1); press_key(4'd1); press_key(4'd1);
        press_key(4'd1); press_key(4'd13);
        repeat(3) @(posedge uut.clk1ms);
        // VERIFY: same password
        clear_ev;
        press_key(4'd1); press_key(4'd1); press_key(4'd1);
        press_key(4'd1); press_key(4'd13);
        repeat(5) @(posedge uut.clk1ms);
        check1("verify correct (new super pass)", ev_correct,    1'b1);
        check1("cp_active cleared",               uut.cp_active, 1'b0);
        press_key(4'd2); // exit
        repeat(3) @(posedge uut.clk1ms);
        key = 1'b0;
        apply_reset;

        // ── Final report ──────────────────────────────────────────────────────
        $display("\n══════════════════════════════════════════════════");
        if (fail_count == 0)
            $display("  ALL %0d CHECKS PASSED", check_count);
        else
            $display("  %0d / %0d CHECKS FAILED", fail_count, check_count);
        $display("══════════════════════════════════════════════════");
        $finish;
    end

endmodule
