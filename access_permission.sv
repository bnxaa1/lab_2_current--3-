module access_permission (
    input logic clk, rstN, srst_access,
    input logic locked, key, enter/*key_press*/, correct, error, timeOut,
    output logic Err_LED, Corr_LED,
    output logic rst_lv, rst_failureCtr, rst_timeoutCtr, increment,
    output logic session_active,
    output logic [2:0]  state_p,
    output logic [1:0]  S); // reset of the timeout should be srst

    // the system will be locked after 4 failures and no one can save the situation other than the supervisor
    // add a failure counter that counts until we have 4 failures. we should reset this counter if it becomes unlocked
    wire [2:0] input_cond;
    assign input_cond = {locked, key, enter};

    typedef enum logic [2:0] {S0, S1, S2, S3, S4, S5, S6} state_e; // S4 unreachable after S3/S4 merge; kept to preserve S5/S6 encoding
    state_e state_reg, state_next;
    assign state_p       = state_reg;
    assign session_active = (state_reg == S3); // high while supervisor session is active

    always_ff @(posedge clk, negedge rstN) begin
        if(!rstN)
            state_reg <= S0; // reset state to S0
        else if(srst_access)
            state_reg <= S0;
        else
            state_reg <= state_next; // update state to next_state on clock edge
    end

    always_comb begin
        rst_lv         = 'b0;
        rst_failureCtr = 'b0;
        rst_timeoutCtr = 'b0;
        state_next     = state_reg;
        Err_LED        = 'b0;
        Corr_LED       = 'b0;
        increment      = 'b0;
        S              = 2'b00;

        case(state_reg)
            S0: begin // starting idle state
                if(input_cond == 3'b001) begin // no lock, no key, enter pressed → user authentication attempt
                    rst_timeoutCtr = 1'b1;    // reset timeout counter on auth start; user path only
                    state_next = S1;
                end
                else if(input_cond == 3'b011 || input_cond == 3'b111)
                    state_next = S2; // shared supervisor authentication state
            end

            S1: begin // user state
                S = 2'b00;
                if(key) begin
                    rst_lv     = 1'b1;   // supervisor inserted key: clear lock_validation FSM + codeStorage counter
                    state_next = S0;     // abort user entry, return to idle
                end
                else if(correct) begin
                    rst_lv         = 1'b1;
                    rst_failureCtr = 1'b1; // user authenticated successfully → clear failure count
                    state_next     = S6;
                end
                else if(error) begin
                    increment  = 1'b1;
                    state_next = S5;
                end
                else if(timeOut) begin
                    rst_lv     = 1'b1;   // clear codeStorage counter + lock_validation FSM on timeout
                    state_next = S0;
                end
            end

            S2: begin // shared supervisor authentication state
                S = 2'b01; //*check it later* supervisor password region
                if(!key) begin
                    rst_lv     = 1'b1;   // supervisor removed key: clear lock_validation FSM + codeStorage counter
                    state_next = S0;     // abort supervisor entry, return to idle
                end
                else if(correct)
                    state_next = S3;     // S3 handles both locked and not-locked via input_cond[2]
                else if(error)
                    state_next = S5;
            end

            S3: begin // supervisor session (locked or not-locked; S4 merged here)
                S = input_cond[2] ? 2'b10 : 2'b01; // input_cond[2] = locked; selects supervisor RAM region
                // exit and unlock handled externally via srst_access and unlock_req → failure counter
            end

            S5: begin // error state
                Err_LED    = 'b1;
                rst_lv     = 1'b1;   // reset codeStorage counter + lock_validation FSM on error
                state_next = S0;
            end

            S6: begin // correct state
                Corr_LED   = 'b1;
                state_next = S0;
            end
        endcase
    end
endmodule
