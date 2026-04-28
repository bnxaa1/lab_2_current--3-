module supervisor_requests(
    input  logic        clk, rstN,
    input  logic        session_active, locked, enter_d, cp_done,
    input  logic [3:0]  switches,
    output logic        exit_req, unlock_req, change_user_req, change_super_req,
    output logic [2:0]  sr_state
);

    typedef enum logic [2:0] {NO_REQUEST, CHANGE_USER_PASSWORD, CHANGE_SUPERVISOR_PASSWORD, EXIT_REQUEST, UNLOCK_REQUEST} cmd_request_e;
    cmd_request_e state_reg, state_next;

    assign exit_req         = (state_reg == EXIT_REQUEST);
    assign unlock_req       = (state_reg == UNLOCK_REQUEST);
    assign change_user_req  = (state_reg == CHANGE_USER_PASSWORD);
    assign change_super_req = (state_reg == CHANGE_SUPERVISOR_PASSWORD);
    assign sr_state         = state_reg;

    always_ff @(posedge clk, negedge rstN) begin
        if(!rstN)
            state_reg <= NO_REQUEST;
        else
            state_reg <= state_next;
    end

    always_comb begin
        state_next = state_reg;

        if(!session_active) begin
            state_next = NO_REQUEST; // session ended — clear any pending command
        end
        else begin
            case(state_reg)
                NO_REQUEST: begin
                    if(enter_d) begin
                        case(switches)
                            4'd1: state_next = CHANGE_USER_PASSWORD;
                            4'd2: state_next = EXIT_REQUEST;
                            4'd3: if(locked) state_next = UNLOCK_REQUEST;
                            4'd4: state_next = CHANGE_SUPERVISOR_PASSWORD;
                            default: ;
                        endcase
                    end
                end

                CHANGE_USER_PASSWORD,
                CHANGE_SUPERVISOR_PASSWORD: begin
                    if(cp_done)
                        state_next = NO_REQUEST; // change_password completed or aborted → ready for next command
                end

                UNLOCK_REQUEST:
                    state_next = NO_REQUEST; // auto-clear after 1 cycle; failure counter cleared by unlock_req pulse

                EXIT_REQUEST:
                    state_next = EXIT_REQUEST; // hold until session_active drops
            endcase
        end
    end
endmodule
