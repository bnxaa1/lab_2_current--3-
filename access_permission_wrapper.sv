module access_permission_wrapper(
    input  logic rstN, srst_access, key, enter, correct, error, clk, srst1,
    output logic Err_LED, srst, Corr_LED, increment, timeOut, locked,
    output logic [2:0] state_p,
    output logic [1:0] S
);

    logic [27:0] twentyBitsCounter;
    logic [2:0]  threeBitsCounter;

    TwentyBitsCounter tbc20(
        .clock(clk),
        .sclr(srst),
        .q(twentyBitsCounter)
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

    assign timeOut = (twentyBitsCounter == 28'd250_000_000);

    assign locked = (threeBitsCounter == 3'd4);
endmodule