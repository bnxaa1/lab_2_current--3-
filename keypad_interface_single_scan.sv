module keypad_interface_single_scan #(
    parameter int unsigned CLK_FREQ_HZ        = 50_000_000,
    parameter int unsigned SCAN_RATE_HZ       = 1_000,
    parameter int unsigned DEBOUNCE_MS        = 20,
    parameter int unsigned SCAN_DIVISOR_RAW   = (SCAN_RATE_HZ == 0) ? CLK_FREQ_HZ : (CLK_FREQ_HZ / SCAN_RATE_HZ),
    parameter int unsigned SCAN_DIVISOR       = (SCAN_DIVISOR_RAW < 1) ? 1 : SCAN_DIVISOR_RAW,
    parameter int unsigned SCAN_CNT_W         = (SCAN_DIVISOR <= 2) ? 1 : $clog2(SCAN_DIVISOR),
    parameter int unsigned DEBOUNCE_TICKS_RAW = (SCAN_RATE_HZ * DEBOUNCE_MS) / 1000,
    parameter int unsigned DEBOUNCE_TICKS     = (DEBOUNCE_TICKS_RAW < 1) ? 1 : DEBOUNCE_TICKS_RAW,
    parameter int unsigned DEBOUNCE_W         = (DEBOUNCE_TICKS <= 2) ? 1 : $clog2(DEBOUNCE_TICKS)
) (
    input  logic       clk,
    input  logic       rstn,
    input  logic [3:0] rows,
    output logic [3:0] cols,
    output logic [3:0] pass,
    output logic       Enter
);

    typedef enum logic [1:0] {
        S_SCAN,
        S_DB_PRESS,
        S_PRESSED,
        S_DB_RELEASE
    } state_t;

    state_t state_reg, state_next;

    logic [3:0] rows_meta, rows_sync;
    logic [3:0] row_latch_reg, row_latch_next, col_latch_reg, col_latch_next;
    logic [3:0] pass_next;
    logic [1:0] scan_col_reg, scan_col_next;
    logic [SCAN_CNT_W-1:0] scan_cnt_reg;
    logic [DEBOUNCE_W-1:0] db_cnt_reg, db_cnt_next;
    logic enter_next, scan_tick;

    function automatic logic [3:0] col_pattern(input logic [1:0] idx);
        col_pattern = ~(4'b0001 << idx);
    endfunction

    function automatic logic single_key_pressed(input logic [3:0] al_rows);
        case (al_rows)
            4'b1110,
            4'b1101,
            4'b1011,
            4'b0111: single_key_pressed = 1'b1;
            default: single_key_pressed = 1'b0;
        endcase
    endfunction

    function automatic [1:0] encode4(input [3:0] al_onehot);
        casez (~al_onehot)
            4'b???1: encode4 = 2'd0;
            4'b??10: encode4 = 2'd1;
            4'b?100: encode4 = 2'd2;
            4'b1000: encode4 = 2'd3;
            default: encode4 = 2'd0;
        endcase
    endfunction

    function automatic [3:0] decode_key(input [1:0] r, input [1:0] c);
        case ({r, c})
            4'hF: decode_key = 4'h1;
            4'hE: decode_key = 4'h2;
            4'hD: decode_key = 4'h3;
            4'hC: decode_key = 4'hA;
            4'hB: decode_key = 4'h4;
            4'hA: decode_key = 4'h5;
            4'h9: decode_key = 4'h6;
            4'h8: decode_key = 4'hB;
            4'h7: decode_key = 4'h7;
            4'h6: decode_key = 4'h8;
            4'h5: decode_key = 4'h9;
            4'h4: decode_key = 4'hC;
            4'h3: decode_key = 4'hE;
            4'h2: decode_key = 4'h0;
            4'h1: decode_key = 4'hF;
            default: decode_key = 4'hD;
        endcase
    endfunction

    assign cols = col_pattern(scan_col_reg);

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            rows_meta <= 4'hF;
            rows_sync <= 4'hF;
        end else begin
            rows_meta <= rows;
            rows_sync <= rows_meta;
        end
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            scan_cnt_reg <= '0;
            scan_tick    <= 1'b0;
        end else if (scan_cnt_reg == SCAN_DIVISOR - 1) begin
            scan_cnt_reg <= '0;
            scan_tick    <= 1'b1;
        end else begin
            scan_cnt_reg <= scan_cnt_reg + 1'b1;
            scan_tick    <= 1'b0;
        end
    end

    always_comb begin
        state_next     = state_reg;
        scan_col_next  = scan_col_reg;
        row_latch_next = row_latch_reg;
        col_latch_next = col_latch_reg;
        db_cnt_next    = db_cnt_reg;
        pass_next      = pass;
        enter_next     = Enter;

        if (scan_tick) begin
            case (state_reg)
                S_SCAN: begin
                    enter_next  = 1'b1;
                    db_cnt_next = '0;

                    if (single_key_pressed(rows_sync)) begin
                        row_latch_next = rows_sync;
                        col_latch_next = col_pattern(scan_col_reg);
                        state_next     = S_DB_PRESS;
                    end else begin
                        scan_col_next = scan_col_reg + 2'd1;
                    end
                end

                S_DB_PRESS: begin
                    if (!single_key_pressed(rows_sync) || (rows_sync != row_latch_reg)) begin
                        state_next  = S_SCAN;
                        db_cnt_next = '0;
                    end else if (db_cnt_reg == DEBOUNCE_TICKS - 1) begin
                        pass_next  = decode_key(encode4(row_latch_reg), encode4(col_latch_reg));
                        enter_next = 1'b0;
                        state_next = S_PRESSED;
                    end else begin
                        db_cnt_next = db_cnt_reg + 1'b1;
                    end
                end

                S_PRESSED: begin
                    if (&rows_sync) begin
                        db_cnt_next = '0;
                        state_next  = S_DB_RELEASE;
                    end
                end

                S_DB_RELEASE: begin
                    if (!(&rows_sync)) begin
                        state_next  = S_PRESSED;
                        db_cnt_next = '0;
                    end else if (db_cnt_reg == DEBOUNCE_TICKS - 1) begin
                        enter_next    = 1'b1;
                        scan_col_next = scan_col_reg + 2'd1;
                        db_cnt_next   = '0;
                        state_next    = S_SCAN;
                    end else begin
                        db_cnt_next = db_cnt_reg + 1'b1;
                    end
                end

                default: begin
                    state_next = S_SCAN;
                end
            endcase
        end
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state_reg     <= S_SCAN;
            scan_col_reg  <= 2'd0;
            row_latch_reg <= 4'hF;
            col_latch_reg <= 4'hF;
            db_cnt_reg    <= '0;
            pass          <= 4'h0;
            Enter         <= 1'b1;
        end else begin
            state_reg     <= state_next;
            scan_col_reg  <= scan_col_next;
            row_latch_reg <= row_latch_next;
            col_latch_reg <= col_latch_next;
            db_cnt_reg    <= db_cnt_next;
            pass          <= pass_next;
            Enter         <= enter_next;
        end
    end

endmodule
