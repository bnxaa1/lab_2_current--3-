`timescale 1ns / 1ps

// Testbench for lock_validation_wrapper
//
// RAM contents (ramm.mif, region 0 = user password):
//   addr 0 → 1
//   addr 1 → 2
//   addr 2 → 3
//   addr 3 → 4
//   addr 4 → 10 (4'b1010, end-of-code marker)
//
// Correct entry sequence: 1, 2, 3, 4, 1010
//
// Timing rationale:
//   clk = 1 kHz (clk1ms, driven directly by testbench — clock1 lives in top level only)
//   clk period = 1 000 000 ns (1 ms)
//   one_pulse_generator debounce = 15 clk cycles = 15 ms
//   PRESS_HOLD / RELEASE_HOLD must exceed 15 ms → use 20 cycles (20 ms)

module tb_lock_validation_wrapper;

    // ── DUT ports ────────────────────────────────────────────────
    logic        clk;
    logic        resetN;
    logic        srst;
    logic        enter_al;
    logic [3:0]  switches;
    logic        error;
    logic        correct;

    // ── DUT ──────────────────────────────────────────────────────
    lock_validation_wrapper dut (
        .clk      (clk),
        .resetN   (resetN),
        .srst     (srst),
        .enter_al (enter_al),
        .switches (switches),
        .error    (error),
        .correct  (correct)
    );

    // ── 1 kHz clock (clk1ms) ─────────────────────────────────────
    localparam CLK_HALF_NS = 500_000;   // 500 us half-period → 1 ms period
    initial clk = 0;
    always #CLK_HALF_NS clk = ~clk;

    // ── Timing constants (in clk cycles, each cycle = 1 ms) ──────
    localparam PRESS_CYCLES   = 20;   // 20 ms hold > 15 ms debounce
    localparam RELEASE_CYCLES = 20;   // 20 ms release debounce

    // ── Task: hard reset ─────────────────────────────────────────
    // resetN held low for 3 clk cycles so codeStorage.ctr sclr fires at
    // a clk posedge (ctr has no async reset — synchronous sclr only).
    // lock_validation FSM resets asynchronously (immediately on negedge resetN).
    // enter_d = 0 during reset prevents any ctr advancement in the mismatch window.
    task apply_reset;
        begin
            resetN   = 1'b0;
            srst     = 1'b0;
            enter_al = 1'b1;   // idle: active-low, not pressed
            switches = 4'd0;
            repeat (3) @(posedge clk);  // hold ≥ 1 clk cycle for counter sclr
            resetN = 1'b1;
            repeat (3) @(posedge clk);  // settle: ctr=0, RAM output valid
        end
    endtask

    // ── Task: synchronous reset (clears FSM + codeStorage counter) ──
    // srst held for 2 clk cycles so both lock_validation FSM and
    // codeStorage counter sclr are captured at a clk posedge.
    // 3-cycle settle covers the 2-cycle RAM read latency after ctr resets.
    task sync_reset;
        begin
            srst = 1'b1;
            repeat (2) @(posedge clk); #1;  // hold: captured at clk posedge
            srst = 1'b0;
            repeat (3) @(posedge clk);      // settle: FSM=S0, ctr=0, code valid
        end
    endtask

    // ── Task: enter one debounced digit ──────────────────────────
    // Sets switches, holds enter_al low past the 15-cycle debounce window,
    // then releases and waits for the release debounce to complete.
    task enter_digit;
        input [3:0] digit;
        begin
            switches = digit;
            @(negedge clk);              // align to falling edge before press
            enter_al = 1'b0;             // press button (active low)
            repeat (PRESS_CYCLES)   @(posedge clk);
            enter_al = 1'b1;             // release button
            repeat (RELEASE_CYCLES) @(posedge clk);
        end
    endtask

    // ── Output monitors ──────────────────────────────────────────
    always @(posedge correct)
        $display("[%0t ns]  >> CORRECT asserted", $time);
    always @(posedge error)
        $display("[%0t ns]  >> ERROR asserted", $time);

    // ── Test sequence ────────────────────────────────────────────
    initial begin
        $display("=== tb_lock_validation_wrapper ===");
        apply_reset;
        $display("[%0t ns] Reset done", $time);

        // ── Test 1: correct sequence ──────────────────────────────
        // Expected: correct=1 after entering 1, 2, 3, 4, 1010
        $display("[%0t ns] Test 1: correct sequence  1-2-3-4-1010", $time);
        enter_digit(4'd1);
        enter_digit(4'd2);
        enter_digit(4'd3);
        enter_digit(4'd4);
        enter_digit(4'b1010);        // end marker (4'b1010 = decimal 10)
        repeat (4) @(posedge clk);
        if (correct)
            $display("[%0t ns] Test 1 PASS", $time);
        else
            $display("[%0t ns] Test 1 FAIL (correct not asserted)", $time);
        sync_reset;

        // ── Test 2: wrong first digit ─────────────────────────────
        // Expected: FSM → S2 on digit 9 (≠ 1), → S3 on end marker
        $display("[%0t ns] Test 2: wrong digit  9-1010", $time);
        enter_digit(4'd9);           // wrong: expected 1
        enter_digit(4'b1010);        // end marker → S3 (error)
        repeat (4) @(posedge clk);
        if (error)
            $display("[%0t ns] Test 2 PASS", $time);
        else
            $display("[%0t ns] Test 2 FAIL (error not asserted)", $time);
        sync_reset;

        // ── Test 3: correct digits, wrong at end-marker position ──
        // Expected: 1,2,3,4 correct, digit 5 wrong (code=1010, switches=9) → S2
        $display("[%0t ns] Test 3: correct digits, wrong end  1-2-3-4-9-1010", $time);
        enter_digit(4'd1);
        enter_digit(4'd2);
        enter_digit(4'd3);
        enter_digit(4'd4);
        enter_digit(4'd9);           // code=1010 here, switches≠1010 → S2
        enter_digit(4'b1010);        // end marker while in S2 → S3
        repeat (4) @(posedge clk);
        if (error)
            $display("[%0t ns] Test 3 PASS", $time);
        else
            $display("[%0t ns] Test 3 FAIL (error not asserted)", $time);
        sync_reset;

        // ── Test 4: early end marker ──────────────────────────────
        // At position 0, code=1 (not 1010); switches=1010 → S3 immediately
        $display("[%0t ns] Test 4: early end marker  1010 at digit 0", $time);
        enter_digit(4'b1010);        // switches=1010 but code=1 → S3
        repeat (4) @(posedge clk);
        if (error)
            $display("[%0t ns] Test 4 PASS", $time);
        else
            $display("[%0t ns] Test 4 FAIL (error not asserted)", $time);
        sync_reset;

        // ── Test 5: srst mid-entry, then correct sequence ─────────
        $display("[%0t ns] Test 5: srst mid-entry, then correct sequence", $time);
        enter_digit(4'd1);
        enter_digit(4'd2);
        sync_reset;                  // reset mid-attempt
        enter_digit(4'd1);
        enter_digit(4'd2);
        enter_digit(4'd3);
        enter_digit(4'd4);
        enter_digit(4'b1010);
        repeat (4) @(posedge clk);
        if (correct)
            $display("[%0t ns] Test 5 PASS", $time);
        else
            $display("[%0t ns] Test 5 FAIL (correct not asserted after mid-entry reset)", $time);
        sync_reset;

        $display("=== simulation complete ===");
        $stop;
    end

endmodule
