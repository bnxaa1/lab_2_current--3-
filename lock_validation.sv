module lock_validation(
    input logic clk,
    input logic resetN,
    input logic srst,
    input logic enter_al,
    input logic done,
    input logic [3:0] code,
    input logic [3:0] switches,
    output logic error,
    output logic correct,
    output logic enter_d,
    output logic [2:0] state_regt
);
//** we should reset the counter before we run this again let both codes have the same srst
    logic eq, end_code;
    typedef enum logic [2:0] {S0, S1, S2, S3} state_check;
    state_check state_reg, state_next;

    one_pulse_generator opg1(
        .enter_al(enter_al),
        .clk(clk),
        .resetN(resetN),
        .enter_d(enter_d)
    );

    assign state_regt = state_reg;
    assign eq = (code == switches);
    assign end_code = (code == 4'b1010);

    always_ff @(posedge clk, negedge resetN) begin
        if(!resetN)
            state_reg <= S0;
        else if(srst)
            state_reg <= S0;
        else
            state_reg <= state_next;
    end

    always_comb begin: Lock_validation
        state_next = state_reg;
        error = 1'b0;
        correct = 1'b0;

        case(state_reg)
            S0: begin // still correct so far
                if(enter_d) begin
                    if(done && eq)
                        state_next = S1;
                    else if(end_code) begin
                        if(eq)
                            state_next = S1;
                        else
                            state_next = S2; // wrong final entry, wait for done/end confirmation before error state
                    end
                    else if (switches == 4'b1010)
                        state_next = S3;
                    else if(!eq)
                        state_next = S2;
                end
            end

            S1: begin
                correct = 1'b1;
                //** reset to enter the code again
            end

            S2: begin // at least one digit is wrong, wait for the attempt to finish
                if(enter_d)
                    if(done || (switches == 4'b1010))
                        state_next = S3;
            end

            S3: begin
                error = 1'b1;
                //** reset to enter the code again
            end
        endcase
    end
endmodule