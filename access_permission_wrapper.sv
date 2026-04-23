module access_permission_wrapper(
    input  logic rstN, srst_access, key, enter, correct, error, clk, srst1,
    output logic Err_LED, srst, Corr_LED, increment, timeOut, locked,
    output logic [2:0] state_p,
    output logic [1:0] S
);

    logic [12:0] ThirteenBitsCounter;
    logic [2:0]  threeBitsCounter;

    thirteenBitsCtr tbc13(
        .clock(clk),
        .sclr(timeout),
        .q(ThirteenBitsCounter)
    );

    ThreeBitsCounter tbc3(
        .clk_en(increment),
        .clock(clk),
        .sclr(srst1),
        .q(threeBitsCounter)
    );

    access_permission ap1(
        .locked(locked),
        .rstN(rstN),
        .srst_access(srst_access),
        .key(key),
        .enter(enter),
        .correct(correct),
        .error(error),
        .timeOut(timeOut),
        .clk(clk),
        .Err_LED(Err_LED),
        .srst(srst),
        .Corr_LED(Corr_LED),
        .increment(increment),
        .state_p(state_p),
        .S(S)
    );

    // clk1ms runs at 1 kHz; 5 000 cycles = 5 s timeout
    assign timeOut = (ThirteenBitsCounter == 13'd5_000); //maybe timeout for 1 cycle so I should reset it

    assign locked = (threeBitsCounter == 3'd4);
endmodule