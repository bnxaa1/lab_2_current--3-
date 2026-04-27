// =============================================================================
// keypad_interface.sv
//
// GPIO_0[35:32] → cols (wires 1–4)
// GPIO_0[31:28] → rows (wires 5–8)
// =============================================================================

module keypad_interface (
    input  logic        clk, rstn,
    inout  logic [3:0]  cols,      // GPIO_0[35:32]
    inout  logic [3:0]  rows,      // GPIO_0[31:28]
    output logic [3:0]  pass,
    output logic        Enter      // active-low, mirrors KEY[0] behaviour
);

    // -------------------------------------------------------------------------
    // Timing parameters  (~763 Hz → ~1.31 ms per cycle)
    // -------------------------------------------------------------------------
    localparam int DEBOUNCE_CYC = 15;   // ~20 ms debounce  (15 × 1.31 ms)
    localparam int SETTLE_CYC   = 2;    // ~2.6 ms settle after direction swap

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE,
        S_DEBOUNCE,
        S_LATCH_ROW,
        S_SETTLE,
        S_LATCH_COL,
        S_PRESSED,
        S_REL_DEBOUNCE
    } state_t;

    state_t     state;
    logic [4:0] cnt;          // 5 bits is enough for max count of 15
    logic [3:0] row_latch;
    logic       cols_oe, rows_oe;

    // -------------------------------------------------------------------------
    // Tri-state GPIO drivers
    // -------------------------------------------------------------------------
    assign cols = cols_oe ? 4'b0000 : 4'bzzzz;
    assign rows = rows_oe ? 4'b0000 : 4'bzzzz;

    // -------------------------------------------------------------------------
    // Active-low one-hot → 2-bit binary priority encoder
    // -------------------------------------------------------------------------
    function automatic [1:0] encode4 (input [3:0] al_onehot);
        casez (~al_onehot)
            4'b???1 : encode4 = 2'd0;
            4'b??10 : encode4 = 2'd1;
            4'b?100 : encode4 = 2'd2;
            4'b1000 : encode4 = 2'd3;
            default : encode4 = 2'd0;
        endcase
    endfunction

    // -------------------------------------------------------------------------
    // Hex keypad layout decoder
    //        Col 0  Col 1  Col 2  Col 3
    //  Row 0:  1      2      3      A
    //  Row 1:  4      5      6      B
    //  Row 2:  7      8      9      C
    //  Row 3:  E      0      F      D
    // -------------------------------------------------------------------------
		function automatic [3:0] decode_key (input [1:0] r, input [1:0] c);
			 case ({r, c})
				  4'hF : decode_key = 4'h1;    4'hE : decode_key = 4'h2;
				  4'hD : decode_key = 4'h3;    4'hC : decode_key = 4'hA;
				  4'hB : decode_key = 4'h4;    4'hA : decode_key = 4'h5;
				  4'h9 : decode_key = 4'h6;    4'h8 : decode_key = 4'hB;
				  4'h7 : decode_key = 4'h7;    4'h6 : decode_key = 4'h8;
				  4'h5 : decode_key = 4'h9;    4'h4 : decode_key = 4'hC;
				  4'h3 : decode_key = 4'hE;    4'h2 : decode_key = 4'h0;
				  4'h1 : decode_key = 4'hF;    4'h0 : decode_key = 4'hD;
			 endcase
		endfunction
    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk, negedge rstn) begin
        if (~rstn) begin
            state     <= S_IDLE;
            cols_oe   <= 1'b1;
            rows_oe   <= 1'b0;
            Enter     <= 1'b1;
            pass      <= 4'h0;
            cnt       <= '0;
            row_latch <= 4'hF;
        end else begin
            case (state)

                S_IDLE : begin
                    cols_oe <= 1'b1;
                    rows_oe <= 1'b0;
                    Enter   <= 1'b1;
                    if (~(&rows)) begin
                        cnt   <= '0;
                        state <= S_DEBOUNCE;
                    end
                end

                S_DEBOUNCE : begin
                    if (&rows)
                        state <= S_IDLE;
                    else if (cnt == DEBOUNCE_CYC - 1) begin
                        cnt   <= '0;
                        state <= S_LATCH_ROW;
                    end else
                        cnt <= cnt + 1'b1;
                end

                S_LATCH_ROW : begin
                    row_latch <= rows;
                    cols_oe   <= 1'b0;
                    rows_oe   <= 1'b1;
                    cnt       <= '0;
                    state     <= S_SETTLE;
                end

                S_SETTLE : begin
                    if (cnt == SETTLE_CYC - 1) begin
                        cnt   <= '0;
                        state <= S_LATCH_COL;
                    end else
                        cnt <= cnt + 1'b1;
                end

                S_LATCH_COL : begin
                    pass    <= decode_key(encode4(row_latch), encode4(cols));
                    Enter   <= 1'b0;
                    cols_oe <= 1'b1;
                    rows_oe <= 1'b0;
                    state   <= S_PRESSED;
                end

                S_PRESSED : begin
                    if (&rows) begin
                        cnt   <= '0;
                        state <= S_REL_DEBOUNCE;
                    end
                end

                S_REL_DEBOUNCE : begin
                    if (~(&rows))
                        state <= S_PRESSED;
                    else if (cnt == DEBOUNCE_CYC - 1) begin
                        Enter <= 1'b1;
                        state <= S_IDLE;
                    end else
                        cnt <= cnt + 1'b1;
                end

            endcase
        end
    end

endmodule
