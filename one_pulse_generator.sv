module one_pulse_generator(
             input logic enter_al/*active low*/, clk, resetN,
             output logic enter_d);
				 
    //debounced one pulse signal
	logic done_clk, st; //timeout counter signal, st to reset the counter
	logic [3:0] ctr;
    typedef enum logic [2:0] {S0, S1, S2, S3, S4} state_e; // typedef: creates a new type, enum: gives a name to a set of values, logic [1:0]: 2-bit logic vector
    state_e state_reg, state_next; //state_e defines the possible values of state and next_state

    always_ff @(posedge clk, negedge resetN) begin
        if(!resetN)
            state_reg <= S0; // reset state to S0
        else
            state_reg <= state_next; // update state to next_state on clock edge
    end

    //debounced pulse generation
    // State transition logic
    always_comb begin: one_pulse_enter
        state_next = state_reg; // default next state is the same as current state
		enter_d = 1'b0;
		st = 1'b0; // don't reset the ctr
        case(state_reg)
            S0: begin
				st = 1'b1;
				if(!enter_al)
                    state_next= S1;
				end
            S1: 
				if(enter_al && done_clk)
                    state_next = S0;
                else if(!enter_al && done_clk)
                    state_next = S2;
            S2: begin
                state_next = S3;
				enter_d= 1'b1;
				end
            S3: begin
				st = 1'b1;
				if(enter_al)
					state_next= S4;
				end
            S4: if(done_clk)
                    state_next = S0;
        endcase
    end
	 
// clk is clk1ms (1 kHz); 15 cycles = 15 ms debounce window
    counter c1(.clock(clk), .sclr(st), .q(ctr), .clk_en(1'b1)); // instantiate the counter module
	assign done_clk = &ctr;
endmodule