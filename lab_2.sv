module lab_2(
    input logic [3:0] switches, input logic enter_al/*active low*/, key, clk, resetN, srst_access,
    output logic error, correct, enter_d, Err_LED, Corr_LED
);

    logic [2:0] state_regt, access_state_p;
    logic done, wren, srst, srst1, increment, timeOut, locked, enter_access, clk1ms;
    logic [3:0] code, dataIn;
    logic [4:0] rStartingAddress, wStartingAddress;
    logic [1:0] S;

    assign wren = 1'b0;
    assign rStartingAddress = (S == 2'b00) ? 5'b00000 : (S == 2'b01) ? 5'b01010 : 5'b10100; // read from 0 for validation, 10/20 for alternate regions
    assign wStartingAddress = 5'b0;
    assign dataIn = 4'b0;
    assign enter_access = enter_d && (switches == 4'd11);
    assign srst1 = 1'b0; // TODO: replace when a dedicated srst1 source is defined by the access-permission path

    codeStorage cs1(
        .clk(clk1ms),
        .wren(wren),
        .ctrRst(srst),
        .clk_en(enter_d),
        .rStartingAddress(rStartingAddress),
        .wStartingAddress(wStartingAddress), // reset the counter before using it
        .dataIn(dataIn), //process of changing the password
        .done(done),
        .dataOut(code)
    );

    access_permission_wrapper apw1(
        .rstN(resetN),
        .srst_access(srst_access),
        .key(key),
        .enter(enter_access),
        .correct(correct),
        .error(error),
        .clk(clk1ms),
        .srst1(srst1),
        .Err_LED(Err_LED),
        .srst(srst),
        .Corr_LED(Corr_LED),
        .increment(increment),
        .timeOut(timeOut),
        .locked(locked),
        .state_p(access_state_p),
        .S(S)
    );
    clock1 clk1(
        .clk(clk),
        .clk_out(clk1ms)
    );
    lock_validation lv1(
        .clk(clk1ms),
        .resetN(resetN),
        .srst(srst),
        .enter_al(enter_al),
        .done(done),
        .code(code),
        .switches(switches),
        .error(error),
        .correct(correct),
        .enter_d(enter_d),
        .state_regt(state_regt)
    );
endmodule