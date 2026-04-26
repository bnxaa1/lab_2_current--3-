module change_password (input  logic        clk, resetN,
    input  logic        start, enter_d, done,    // start: 1-cycle pulse from supervisor_requests; done: codeStorage ctr==9
    input  logic        lv_correct, lv_error,    // lock_validation outputs
    input  logic [3:0]  switches,                // digit input
    input  logic [5:0]  active_addr,             // current active region start (from wrapper)
    output logic        cp_active,               // 1 while running; mux selector in lab_2
    output logic        wren, clk_en_override,   // wren: RAM write enable; clk_en_override: drives codeStorage clk_en
    output logic        ctrRst, srst_lv,         // ctrRst: resets codeStorage counter; srst_lv: holds lock_validation in reset during ENTRY
    output logic        cp_complete, cp_fail,    // cp_complete: swap active region; cp_fail: abort → supervisor_requests NO_REQUEST
    output logic [3:0]  dataIn,                  // write data to inactive region
    output logic [5:0]  wStartAddr, rStartAddr   // inactive region: write target and read source
);
    // inactive region = active region with bit 4 flipped
    logic [5:0] inactive_addr;
    assign inactive_addr = active_addr ^ 6'b010000;

    typedef enum logic [2:0] {IDLE, ENTRY_RST, ENTRY, VERIFY_RST, VERIFY_WAIT, VERIFY, DONE, ERROR} state_e;
    state_e state_reg, state_next;

    always_ff @(posedge clk, negedge resetN) begin
        if (!resetN) state_reg <= IDLE;
        else         state_reg <= state_next;
    end

    always_comb begin
        state_next      = state_reg;
        cp_active       = 1'b1;
        wren            = 1'b0;
        dataIn          = 4'b0;
        wStartAddr      = inactive_addr;
        rStartAddr      = inactive_addr;
        clk_en_override = 1'b0;
        ctrRst          = 1'b0;
        srst_lv         = 1'b0;
        cp_complete     = 1'b0;
        cp_fail         = 1'b0;

        case (state_reg)
            IDLE: begin
                cp_active  = 1'b0;
                if (start) state_next = ENTRY_RST;
            end

            ENTRY_RST: begin
                ctrRst     = 1'b1;
                srst_lv    = 1'b1;
                state_next = ENTRY;
            end

            ENTRY: begin
                srst_lv = 1'b1;
                dataIn  = switches;
                if (enter_d) begin
                    wren            = 1'b1;
                    clk_en_override = 1'b1;
                    if (switches == 4'b1010 || done)
                        state_next = VERIFY_RST;
                end
            end

            VERIFY_RST: begin
                ctrRst     = 1'b1;
                srst_lv    = 1'b1;
                state_next = VERIFY_WAIT;
            end

            VERIFY_WAIT: begin
                state_next = VERIFY; // one idle cycle for RAM registered-output latency
            end

            VERIFY: begin
                if (enter_d)     clk_en_override = 1'b1;
                if (lv_correct)  state_next = DONE;
                else if (lv_error) state_next = ERROR;
            end

            DONE: begin
                cp_complete = 1'b1;
                state_next  = IDLE;
            end

            ERROR: begin
                cp_fail    = 1'b1;
                state_next = IDLE;
            end

            default: state_next = IDLE;
        endcase
    end

endmodule
