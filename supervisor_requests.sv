module supervisor_requests(
    input  logic clk,
    input  logic rstN,
    input  logic [2:0] access_state,
    input  logic [2:0] cmd_request_in,
    output logic [2:0] cmd_request
);

    typedef enum logic [2:0] {S0, S1, S2, S3, S4, S5, S6} access_state_e;
    typedef enum logic [2:0] {NO_REQUEST, CHANGE_USER_PASSWORD, CHANGE_SUPERVISOR_PASSWORD, EXIT_REQUEST, UNLOCK_REQUEST} cmd_request_e;
    access_state_e access_state_t;
    cmd_request_e cmd_request_reg, cmd_request_next;

    always_ff @(posedge clk, negedge rstN) begin
        if(!rstN)
            cmd_request_reg <= NO_REQUEST;
        else
            cmd_request_reg <= cmd_request_next;
    end

    always_comb begin
        access_state_t = access_state_e'(access_state);
        cmd_request_next = cmd_request_reg;

        if(!(access_state_t == S3 || access_state_t == S4)) begin
            cmd_request_next = NO_REQUEST;
        end
        else begin
            case(cmd_request_reg)
                NO_REQUEST: begin
                    case(cmd_request_in)
                        CHANGE_USER_PASSWORD:
                            cmd_request_next = CHANGE_USER_PASSWORD;
                        CHANGE_SUPERVISOR_PASSWORD:
                            cmd_request_next = CHANGE_SUPERVISOR_PASSWORD;
                        EXIT_REQUEST:
                            cmd_request_next = EXIT_REQUEST;
                        UNLOCK_REQUEST:
                            if(access_state_t == S4)
                                cmd_request_next = UNLOCK_REQUEST;
                    endcase
                end

                CHANGE_USER_PASSWORD,
                CHANGE_SUPERVISOR_PASSWORD,
                UNLOCK_REQUEST: begin
                    if(cmd_request_in == EXIT_REQUEST)
                        cmd_request_next = EXIT_REQUEST;
                end

                EXIT_REQUEST:
                    cmd_request_next = EXIT_REQUEST;
            endcase
        end

        cmd_request = cmd_request_reg;
    end
endmodule