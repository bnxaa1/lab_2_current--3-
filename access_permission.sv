module access_permission (input logic locked, rstN, srst_access, key, enter/*key_press*/, correct, error, timeOut, clk,
									output logic Err_LED, srst/*for the timeout*/, Corr_LED, increment,
									output logic [2:0] state_p,
									output logic [1:0] S); // reset of the timeout should be srst

	// the system will be locked after 4 failures and no one can save the situation other than the supervisor
	// add a failure counter that counts until we have 4 failures. we should reset this counter if it becomes unlocked
	wire [2:0] input_cond;
	assign input_cond = {locked, key, enter};

	typedef enum logic [2:0] {S0, S1, S2, S3, S4, S5, S6} state_e;
	state_e state_reg, state_next;
	assign state_p = state_reg;

	always_ff @(posedge clk, negedge rstN) begin
        if(!rstN)
            state_reg <= S0; // reset state to S0
        else if(srst_access)
            state_reg <= S0;
        else
            state_reg <= state_next; // update state to next_state on clock edge
	end

	always_comb begin
		srst = 'b0;
		state_next = state_reg;
		Err_LED = 'b0;
		Corr_LED = 'b0;
		increment = 'b0;
		S = 2'b00;

		case(state_reg)
			S0: begin // starting / idle state
				srst = 'b1;
				if(input_cond == 3'b001)
					state_next = S1; // user path
				else if(input_cond == 3'b011 || input_cond == 3'b111)
					state_next = S2; // shared supervisor authentication state
			end

			S1: begin // user state
				S = 2'b00;
				if(correct) begin
					srst = 1'b1;
					state_next = S6;
				end
				else if(error) begin
					increment = 1'b1;
					state_next = S5;
				end
				else if(timeOut)
					state_next = S0;
			end

			S2: begin // shared supervisor authentication state
				S = 2'b01; // supervisor password region
				if(correct)
					state_next = locked ? S4 : S3;
				else if(error)
					state_next = S5;
			end

			S3: begin // true supervisor session while system is not locked
				S = 2'b01; //** move it later to supervisor requests
			end

			S4: begin // true supervisor session while system is locked
				S = 2'b10;
			end

			S5: begin // error state
				Err_LED = 'b1;
				state_next = S0;
			end

			S6: begin // correct state
				Corr_LED = 'b1;
				state_next = S0;
			end
		endcase
	end
endmodule
					
			
		
