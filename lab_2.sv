module lab_2(
    input logic [3:0] switches, input logic enter_al/*active low*/, key, clk, resetN, srst_access,
    output logic error, correct, Err_LED, Corr_LED
);

    logic [2:0] access_state_p;
    logic rst_lv, rst_failureCtr, increment, timeOut, locked, clk1ms;

    assign rst_failureCtr = 1'b0; // TODO: connect to supervisor unlock when supervisor_requests is integrated

    access_permission_wrapper apw1(
        .resetN        (resetN),
        .srst_access   (srst_access),
        .key           (key),
        .enter_al      (enter_al),
        .switches      (switches),
        .clk           (clk1ms),
        .rst_failureCtr (rst_failureCtr),
        .wren          (1'b0),   // disabled until change_password is integrated
        .dataIn        (4'b0),
        .Err_LED       (Err_LED),
        .rst_lv        (rst_lv),
        .Corr_LED    (Corr_LED),
        .increment   (increment),
        .timeOut     (timeOut),
        .locked      (locked),
        .correct     (correct),
        .error       (error),
        .state_p     (access_state_p)
    );

    clock1 clk1(
        .clk(clk),
        .clk_out(clk1ms)
    );

endmodule
