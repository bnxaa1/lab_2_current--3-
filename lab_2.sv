module lab_2(
    input  logic       key, clk, resetN, srst_access, enter_al,
    input  logic [3:0] switches,
    output logic       error, correct, Err_LED, Corr_LED, Lock_LED, session_active,
    output logic [3:0] dbg_code, dbg_switches, dbg_flags1, dbg_flags0, keypad_pass_dbg,
    output logic [5:0] dbg_rAddr,
    output logic [2:0] dbg_state, sr_state
);

    logic        clk1ms;               // lab_2 now consumes the already-divided 1 kHz clock
    logic        locked, timeOut, rst_lv, increment;
    logic        exit_req, unlock_req, change_user_req, change_super_req;
    logic        cp_active, cp_complete, cp_fail, cp_done, is_supervisor, cp_wren;
    logic        cp_ctrRst, cp_srst_lv;
    logic        enter_d, done;
    logic        ap_corr_pulse, ap_err_pulse;  // 1-cycle pulses from access_permission → leds FSM
    logic        session_active_r, sup_corr_pulse; // edge detector for supervisor auth confirmation
    logic [2:0]  access_state_p;
    logic [3:0]  dataIn_cp;
    logic [5:0]  target_addr, active_addr;

    assign clk1ms = clk;
    assign dbg_switches = switches;
    assign keypad_pass_dbg = switches;  // dedicated raw keypad pass value for top-level HEX debug
    assign dbg_state    = access_state_p;
    assign dbg_flags1   = {locked, session_active, done, enter_d};
    assign dbg_flags0   = {cp_active, cp_complete, correct, error};

    assign cp_done       = cp_complete | cp_fail;         // release supervisor_requests from CHANGE state
    assign is_supervisor = change_super_req;              // stable throughout change_password session
    assign sup_corr_pulse = session_active & ~session_active_r; // 1-cycle pulse on supervisor auth success

    always_ff @(posedge clk1ms, negedge resetN)
        if (!resetN) session_active_r <= 1'b0;
        else         session_active_r <= session_active;

    // ── Access permission wrapper ─────────────────────────────────────────────
    access_permission_wrapper apw1(
        .resetN        (resetN),
        .srst_access   (srst_access | exit_req), // testbench srst OR supervisor EXIT
        .key           (key),
        .enter_al      (enter_al),
        .switches      (switches),
        .clk           (clk1ms),
        .rst_failureCtr(1'b0),                   // unlock handled internally via unlock_req
        .unlock_req    (unlock_req),
        .cp_complete   (cp_complete),
        .is_supervisor (is_supervisor),
        .cp_active     (cp_active),
        .cp_ctrRst     (cp_ctrRst),
        .cp_srst_lv    (cp_srst_lv),
        .wren          (cp_wren),
        .dataIn        (dataIn_cp),
        .target_addr   (target_addr),
        .Err_LED       (ap_err_pulse),
        .rst_lv        (rst_lv),
        .Corr_LED      (ap_corr_pulse),
        .increment     (increment),
        .timeOut       (timeOut),
        .locked        (locked),
        .correct       (correct),
        .error         (error),
        .state_p       (access_state_p),
        .session_active(session_active),
        .enter_d       (enter_d),
        .done          (done),
        .active_addr   (active_addr),
        .dbg_code      (dbg_code),
        .dbg_rAddr     (dbg_rAddr)
    );

    // ── Supervisor requests ───────────────────────────────────────────────────
    supervisor_requests sr1(
        .clk             (clk1ms),
        .rstN            (resetN),
        .session_active  (session_active),
        .locked          (locked),
        .enter_d         (enter_d),
        .cp_done         (cp_done),
        .switches        (switches),
        .exit_req        (exit_req),
        .unlock_req      (unlock_req),
        .change_user_req (change_user_req),
        .change_super_req(change_super_req),
        .sr_state        (sr_state)
    );

    // ── Change password ───────────────────────────────────────────────────────
    change_password cp1(
        .clk            (clk1ms),
        .resetN         (resetN),
        .start          (change_user_req | change_super_req),
        .enter_d        (enter_d),
        .done           (done),
        .lv_correct     (correct),
        .lv_error       (error),
        .switches       (switches),
        .active_addr    (active_addr),
        .cp_active      (cp_active),
        .wren           (cp_wren),
        .clk_en_override(),              // redundant: enter_d already drives codeStorage clk_en
        .ctrRst         (cp_ctrRst),
        .srst_lv        (cp_srst_lv),
        .cp_complete    (cp_complete),
        .cp_fail        (cp_fail),
        .dataIn         (dataIn_cp),
        .target_addr    (target_addr)
    );

    // ── LEDs ──────────────────────────────────────────────────────────────────
    leds led1(
        .clk        (clk1ms),
        .rstN       (resetN),
        .corr_in    (ap_corr_pulse | sup_corr_pulse | cp_complete | unlock_req),
        .err_in     (ap_err_pulse),
        .timeout_in (timeOut),
        .locked_in  (locked),
        .Corr_LED   (Corr_LED),
        .Err_LED    (Err_LED),
        .Lock_LED   (Lock_LED)
    );

endmodule
