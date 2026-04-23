module clock1 ( //created a clock with a period of 1ms
    input  logic clk,
    output logic clk_out
);
    logic [15:0] q;
    logic rst;

    sixteenbitsctr clk1(.clock(clk), .sclr(rst), .q(q));

    assign rst = (q == 16'd49999);
    assign clk_out = (q < 16'd25000);
endmodule