// Behavioral simulation-only replacement for ram.v (Altera altsyncram IP).
// Same module name and port list as ram.v — no changes needed in codeStorage.sv.
// Initialized to match ramm.mif content (DEPTH=64, WIDTH=4).
// 1-cycle read latency matches altsyncram outdata_reg_b = "CLOCK0".

module ram (clock, data, rdaddress, wraddress, wren, q);
    input        clock;
    input  [3:0] data;
    input  [5:0] rdaddress;
    input  [5:0] wraddress;
    input        wren;
    output [3:0] q;

    reg [3:0] mem [0:63];
    reg [3:0] q_reg;

    assign q = q_reg;

    integer i;
    initial begin
        // Zero all locations first
        for (i = 0; i < 64; i = i + 1)
            mem[i] = 4'd0;
        // User A password — addr 0-4 (region A, key=0, user_active=0)
        mem[0] = 4'd1;  mem[1] = 4'd2;  mem[2] = 4'd3;
        mem[3] = 4'd4;  mem[4] = 4'd10;
        // User B (addr 16-31) — blank until change_password writes to it
        // Super A password — addr 32-36 (region A, key=1, super_active=0)
        mem[32] = 4'd2; mem[33] = 4'd0; mem[34] = 4'd2;
        mem[35] = 4'd6; mem[36] = 4'd10;
        // Super B (addr 48-63) — blank until change_password writes to it
    end

    always @(posedge clock) begin
        if (wren)
            mem[wraddress] <= data;
        q_reg <= mem[rdaddress];
    end

endmodule
