module leds (
    input  logic clk, rstN,
    input  logic corr_in, err_in,   // 1-cycle input pulses from access_permission
    input  logic timeout_in,         // 1-cycle pulse on session timeout
    input  logic locked_in,          // level: system locked after 4 failures
    output logic Corr_LED, Err_LED, Lock_LED
);
    logic [11:0] ctr;
    logic [1:0]  blink_cnt_reg, blink_cnt_next;
    logic        ctr_rst;

    typedef enum logic [2:0] {IDLE, CORR_HOLD, BLINK_ON, BLINK_OFF, TIMEOUT_HOLD} state_e;
    state_e state_reg, state_next;

    assign Lock_LED = locked_in;

    twelveBitsCounter tbc12 (
        .clock (clk),
        .sclr  (ctr_rst),
        .q     (ctr)
    );

    always_ff @(posedge clk, negedge rstN) begin
        if (!rstN) begin
            state_reg     <= IDLE;
            blink_cnt_reg <= 2'd0;
        end else begin
            state_reg     <= state_next;
            blink_cnt_reg <= blink_cnt_next;
        end
    end

    always_comb begin
        state_next     = state_reg;
        blink_cnt_next = blink_cnt_reg;
        Corr_LED       = 1'b0;
        Err_LED        = 1'b0;
        ctr_rst        = 1'b0;

        case (state_reg)
            IDLE: begin
                if (corr_in) begin
                    ctr_rst    = 1'b1;
                    state_next = CORR_HOLD;
                end else if (err_in) begin
                    ctr_rst        = 1'b1;
                    blink_cnt_next = 2'd0;
                    state_next     = BLINK_ON;
                end else if (timeout_in) begin
                    ctr_rst    = 1'b1;
                    state_next = TIMEOUT_HOLD;
                end
            end

            CORR_HOLD: begin
                Corr_LED = 1'b1;
                if (&ctr) begin   // 4 096 ms at 1 kHz — natural 12-bit overflow, no magic number
                    ctr_rst    = 1'b1;
                    state_next = IDLE;
                end
            end

            BLINK_ON: begin
                Err_LED = 1'b1;
                if (ctr[8]) begin  // 256 ms at 1 kHz — bit 8 goes high, no magic number
                    ctr_rst    = 1'b1;
                    state_next = BLINK_OFF;
                end
            end

            BLINK_OFF: begin
                if (ctr[8]) begin  // 256 ms off
                    ctr_rst = 1'b1;
                    if (blink_cnt_reg == 2'd2) begin
                        state_next = IDLE;
                    end else begin
                        blink_cnt_next = blink_cnt_reg + 2'd1;
                        state_next     = BLINK_ON;
                    end
                end
            end

            TIMEOUT_HOLD: begin
                Err_LED = 1'b1;
                if (corr_in) begin
                    ctr_rst    = 1'b1;
                    state_next = CORR_HOLD;
                end else if (err_in) begin
                    ctr_rst        = 1'b1;
                    blink_cnt_next = 2'd0;
                    state_next     = BLINK_ON;
                end
            end

            default: state_next = IDLE;
        endcase
    end

endmodule
