module leds (
    input  logic clk, rst, corr_led, err_led,
    output logic corr_led_out, err_led_out
);
    logic [3:0] q;
    logic sclr, clk_slow;

    // 4-bit counter counts 0–14 then resets; period = 15 × clk
    counter c1(
        .clock  (clk),
        .sclr   (sclr),
        .clk_en (1'b1),
        .q      (q)
    );

    assign sclr     = (q > 4'd12);   // reset at 13 → 14-cycle period (even)
    assign clk_slow = (q > 4'd6);    // high for cycles 7–13, low for 0–6 → 50% duty

endmodule
