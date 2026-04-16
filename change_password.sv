module change_pass (
    input  logic       clk,
    input  logic       resetN,
    input  logic       start_change_pass,   // start when supervisor chooses change password
    input  logic       enter_d,            // one pulse per keypad digit
    input  logic [3:0] switches,            // keypad digit (0..9)

    // signals coming from lock_validation
    input  logic       lv_done,
    input  logic       lv_correct,

    // data read from memory during copy phase
    input  logic [3:0] mem_data_out,

    // outputs to memory
    output logic       wren,
    output logic [4:0] wAddress,
    output logic [3:0] dataIn,
	 
    output logic [4:0] rAddress,

    // outputs to lock_validation
    output logic       lv_start,       // tells it to start validating now
    output logic [4:0] lv_startingAddress,// where the first new pass is storesd in the mem

    // status outputs
    output logic       change_done, // This becomes 1 when the password change finished successfully.
    output logic       confirm_error //This becomes 1 when the second entered password did not match the first one.
);

  // using these we can soecifiy the intial adresses of the passwords 
    localparam USER_START = 5'd0;
    localparam TEMP_START = 5'd10;

    typedef enum logic [2:0] {
        S_IDLE,
        S_STORE_FIRST,
        S_STORE_TERM,
        S_START_VALIDATE,
        S_WAIT_VALIDATE,
        S_COPY_TO_USER,
        S_DONE,
        S_ERROR
    } state_t;

    state_t state, next_state;

    logic [2:0] store_count;   // counts first entered password digits
    logic [2:0] copy_count;    // counts copy steps from temp to user


    always_ff @(posedge clk or negedge resetN) begin
        if (!resetN) begin
            state       <= S_IDLE;
            store_count <= 3'd0;
            copy_count  <= 3'd0;
        end
        else begin
            state <= next_state;

            case (state)

                S_IDLE: begin
                    if (start_change_pass) begin
                        store_count <= 3'd0;
                        copy_count  <= 3'd0;
                    end
                end

                // first entered password is stored in TEMP memory
                S_STORE_FIRST: begin
                    if (enter_d)
                        store_count <= store_count + 3'd1;
                end

                // after successful validation, start copying from temp to user
                S_WAIT_VALIDATE: begin
                    if (lv_done && lv_correct)
                        copy_count <= 3'd0;
                end

                S_COPY_TO_USER: begin
                    if (mem_data_out != 4'd10)
                        copy_count <= copy_count + 3'd1;
                end

                S_DONE, S_ERROR: begin
                    store_count <= 3'd0;
                    copy_count  <= 3'd0;
                end

                default: begin
                    store_count <= store_count;
                    copy_count  <= copy_count;
                end
            endcase
        end
    end


    always_comb begin
        // defaults
        next_state         = state;

        wren               = 1'b0;
        wAddress           = 5'd0;
        dataIn             = 4'd0;

        rAddress           = 5'd0;

        lv_start           = 1'b0;
        lv_startingAddress = TEMP_START;

        change_done        = 1'b0;
        confirm_error      = 1'b0;

        case (state)

           
            // wait for start request
            S_IDLE: begin
                if (start_change_pass)
                    next_state = S_STORE_FIRST;
            end

            // store first entered password into temp memory
            // digit by digit from keypad
            S_STORE_FIRST: begin
                if (enter_d) begin
                    wren     = 1'b1;
                    wAddress = TEMP_START + store_count;
                    dataIn   = switches;

                    if (store_count == 3'd3)
                        next_state = S_STORE_TERM;
                end
            end

            // store terminator 10 after the 4 digits
            S_STORE_TERM: begin
                wren     = 1'b1;
                wAddress = TEMP_START + 3'd4;
                dataIn   = 4'd10;
                next_state = S_START_VALIDATE;
            end

            // start lock_validation
            // lock_validation compares the second entered
            // password against the password at TEMP_START
            S_START_VALIDATE: begin
                lv_start = 1'b1;
                next_state = S_WAIT_VALIDATE;
            end

            // wait for lock_validation result
            S_WAIT_VALIDATE: begin
                if (lv_done) begin
                    if (lv_correct)
                        next_state = S_COPY_TO_USER;
                    else
                        next_state = S_ERROR;
                end
            end


            // copy from TEMP memory to USER memory
            // stop when value 10 is reached
            S_COPY_TO_USER: begin
                rAddress = TEMP_START + copy_count;

                wren     = 1'b1;
                wAddress = USER_START + copy_count;
                dataIn   = mem_data_out;

                if (mem_data_out == 4'd10)
                    next_state = S_DONE;
            end

				
            // success
            S_DONE: begin
                change_done = 1'b1;
                next_state  = S_IDLE;
            end

				
            // confirdigit_inmation error
            S_ERROR: begin
                confirm_error = 1'b1;
                next_state    = S_IDLE;
            end

            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

endmodule
