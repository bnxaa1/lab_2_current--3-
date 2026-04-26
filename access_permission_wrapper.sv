module access_permission_wrapper(
    input  logic        resetN,       // shared async reset (rstN for ap1, resetN for lvw1)
    input  logic        srst_access,  // sync reset for access_permission FSM only
    input  logic        key,
    input  logic        enter_al,     // active-low enter button → lock_validation_wrapper
    input  logic [3:0]  switches,
    input  logic        clk,          // clk1ms (1 kHz) from top level
    input  logic        rst_failureCtr,      // sync reset for failure counter (ThreeBitsCounter)
    input  logic        unlock_req,          // supervisor unlock pulse → clears ThreeBitsCounter
    input  logic        cp_complete,         // password change verified → flip active region pointer
    input  logic        is_supervisor,       // 1 if supervisor password was changed, 0 if user
    input  logic        wren,         // write enable for change_password path (0 until integrated)
    input  logic [3:0]  dataIn,       // write data  for change_password path (0 until integrated)
    output logic        Err_LED,
    output logic        rst_lv,       // resets lock_validation FSM + codeStorage counter
    output logic        Corr_LED,
    output logic        increment,    // pulses once per wrong attempt → failure counter
    output logic        timeOut,
    output logic        locked,
    output logic        correct,
    output logic        error,
    output logic [2:0]  state_p,
    output logic        session_active
);

    logic [12:0] ThirteenBitsCounter;
    logic [2:0]  threeBitsCounter;
    logic [1:0]  S;                           // region select from access_permission (reserved, unused for addressing)
    logic [5:0]  rStartingAddress, wStartingAddress;
    logic        user_active, super_active; // 0=region A, 1=region B; flipped on cp_complete
    logic        enter_d, enter_access;
    logic        rst_timeoutCtr;              // sclr for the 13-bit timeout counter
    logic        ap_rst_failureCtr;          // rst_failureCtr from access_permission (user correct path)
    logic        ap_rst_timeoutCtr;          // rst_timeoutCtr from access_permission (fires on S0→S1 only)
    logic        effective_rst_lv;           // rst_lv OR srst_access: ensures srst_access also resets codeStorage + lock_validation

    // ── Address mux ───────────────────────────────────────────────────────────
    // Read address is resolved from key BEFORE the first enter press.
    // codeStorage counter resets to 0 on every return to S0 (rst_lv fires in all S→S0 transitions).
    // When the user presses enter, ctr advances from the correct base address.
    //   key=0  →  user region A/B   (addr[5:4]=2'b00 or 2'b01, selected by user_active)
    //   key=1  →  super region A/B  (addr[5:4]=2'b10 or 2'b11, selected by super_active)
    // bit 4 is the swap bit — flipped by cp_complete via user_active/super_active registers
    assign rStartingAddress = {key, key ? super_active : user_active, 4'b0000};

    always_ff @(posedge clk, negedge resetN) begin
        if (!resetN) begin
            user_active  <= 1'b0;
            super_active <= 1'b0;
        end else if (cp_complete) begin
            if (is_supervisor) super_active <= ~super_active;
            else               user_active  <= ~user_active;
        end
    end

    // Write address tracks read address for now (wren=0 until change_password is integrated).
    // supervisor_requests will drive wStartingAddress separately in a later phase.
    assign wStartingAddress = rStartingAddress;

    // ── Timeout and lock thresholds ───────────────────────────────────────────
    assign timeOut       = (ThirteenBitsCounter == 13'd5_000); // 5 s @ 1 kHz
    assign rst_timeoutCtr   = timeOut | ap_rst_timeoutCtr | srst_access; // self-reset on fire; reset on S0→S1 (user auth start); reset on srst_access (session exit)
    assign effective_rst_lv = rst_lv | srst_access;              // srst_access propagates reset to all submodules
    assign locked        = (threeBitsCounter    == 3'd4);

    // First digit press IS the authentication trigger — no separate start signal needed.
    assign enter_access = enter_d;

    // ── Counter instances ─────────────────────────────────────────────────────
    thirteenBitsCtr tbc13(
        .clock(clk),
        .sclr(rst_timeoutCtr),
        .q(ThirteenBitsCounter)
    );

    ThreeBitsCounter tbc3(
        .clk_en(increment),
        .clock(clk),
        /*we should have a rst for the whole wrapper not a signal only for the failure counter*/
        .sclr(rst_failureCtr | ap_rst_failureCtr | unlock_req), // supervisor unlock pulse OR user correct OR external reset
        .q(threeBitsCounter)
    );

    // ── access_permission FSM ─────────────────────────────────────────────────
    access_permission ap1(
        .locked      (locked),
        .rstN        (resetN),
        .srst_access (srst_access),
        .key         (key),
        .enter       (enter_access),
        .correct     (correct),
        .error       (error),
        .timeOut     (timeOut),
        .clk         (clk),
        .Err_LED     (Err_LED),
        .rst_lv      (rst_lv),
        .Corr_LED    (Corr_LED),
        .increment       (increment),
        .rst_failureCtr  (ap_rst_failureCtr),
        .rst_timeoutCtr  (ap_rst_timeoutCtr),
        .state_p         (state_p),
        .session_active  (session_active),
        .S               (S)
    );

    // ── lock_validation_wrapper ───────────────────────────────────────────────
    // correct and error are driven by lvw1 and read back by ap1 — one driver, two readers.
    // enter_d is gated inside lvw1: blocked when locked && !key to prevent spurious counter/FSM advances.
    lock_validation_wrapper lvw1(
        .clk              (clk),
        .resetN           (resetN),
        .rst_lv           (effective_rst_lv),
        .enter_al         (enter_al),
        .switches         (switches),
        .rStartingAddress (rStartingAddress),
        .wStartingAddress (wStartingAddress),
        .wren             (wren),
        .dataIn           (dataIn),
        .locked           (locked),
        .key              (key),
        .error            (error),
        .correct          (correct),
        .enter_d          (enter_d)
    );

endmodule
