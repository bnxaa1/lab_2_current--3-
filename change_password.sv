module change_password (input  logic        clk, resetN,
    input  logic        start, enter_d, done,    // start: level from supervisor_requests; done: codeStorage ctr==9
    input  logic        lv_correct, lv_error,    // lock_validation outputs
    input  logic [3:0]  switches,                // digit input
    input  logic [5:0]  active_addr,             // current active region start (from wrapper)
    output logic        cp_active,               // 1 while running; mux selector in lab_2
    output logic        wren, clk_en_override,   // wren: RAM write enable; clk_en_override: drives codeStorage clk_en
    output logic        ctrRst, srst_lv,         // ctrRst: resets codeStorage counter; srst_lv: holds lock_validation in reset during ENTRY
    output logic        cp_complete, cp_fail,    // cp_complete: swap active region; cp_fail: abort → supervisor_requests NO_REQUEST
    output logic [3:0]  dataIn,                  // write data to inactive region
    output logic [5:0]  target_addr              // inactive region; lab_2 muxes into both rStartingAddress and wStartingAddress
);
    // inactive region = active region with bit 4 flipped
    assign target_addr = active_addr ^ 6'b010000;

    typedef enum logic [2:0] {IDLE, ENTRY, VERIFY, DONE, ERROR} state_e;
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
        clk_en_override = 1'b0;
        ctrRst          = 1'b0;
        srst_lv         = 1'b0;
        cp_complete     = 1'b0;
        cp_fail         = 1'b0;

        case (state_reg)
            IDLE: begin
                cp_active  = 1'b0;
                if (start) begin
                    ctrRst     = 1'b1; // Mealy: reset counter and lock_validation on transition to ENTRY
                    srst_lv    = 1'b1;
                    state_next = ENTRY;
                end
            end

            ENTRY: begin
                srst_lv = 1'b1;
                wren    = 1'b1;   // continuously armed so RAM captures switches exactly at the enter_d clock edge
                dataIn  = switches;
                if (enter_d) begin
                    clk_en_override = 1'b1;
                    if (switches == 4'b1101 || done) begin
                        ctrRst     = 1'b1; // Mealy: reset counter and lock_validation on transition to VERIFY; sclr has priority over clk_en
                        srst_lv    = 1'b1;
                        state_next = VERIFY;
                    end
                end
            end

            VERIFY: begin
                //problem when we change the reading address we will have to wait one cycle to have the data at output because of a registered output
                if (enter_d)       clk_en_override = 1'b1; //enter has 15 cycles problem solved
                if (lv_correct)    state_next = DONE;
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
