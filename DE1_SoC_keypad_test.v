// =============================================================================
// DE1_SoC_keypad_test.v — standalone keypad_interface test top-level
//
// What each output shows:
//   HEX0        : last decoded key value (hex digit 0–F)
//   LEDR[3:0]   : same key value as individual bits
//   LEDR[4]     : Enter active (high = key currently held/detected)
//   HEX1–HEX5  : blank
//   LEDR[9:5]   : off
//
// Physical connections (same as lab_2 wiring):
//   cols → GPIO_0[35:32]   rows → GPIO_0[31:28]
//   KEY[0]  → resetN (active-low)
//
// Keypad layout decoded by keypad_interface:
//        Col3  Col2  Col1  Col0
//  Row3:  1     2     3     A
//  Row2:  4     5     6     B
//  Row1:  7     8     9     C
//  Row0:  E     0     F     D
// =============================================================================

module DE1_SoC_keypad_test(

      output             ADC_CONVST,
      output             ADC_DIN,
      input              ADC_DOUT,
      output             ADC_SCLK,
      input              AUD_ADCDAT,
      inout              AUD_ADCLRCK,
      inout              AUD_BCLK,
      output             AUD_DACDAT,
      inout              AUD_DACLRCK,
      output             AUD_XCK,
      input              CLOCK2_50,
      input              CLOCK3_50,
      input              CLOCK4_50,
      input              CLOCK_50,
      output      [12:0] DRAM_ADDR,
      output      [1:0]  DRAM_BA,
      output             DRAM_CAS_N,
      output             DRAM_CKE,
      output             DRAM_CLK,
      output             DRAM_CS_N,
      inout       [15:0] DRAM_DQ,
      output             DRAM_LDQM,
      output             DRAM_RAS_N,
      output             DRAM_UDQM,
      output             DRAM_WE_N,
      output             FAN_CTRL,
      output             FPGA_I2C_SCLK,
      inout              FPGA_I2C_SDAT,
      inout     [35:0]   GPIO_0,
      inout     [35:0]   GPIO_1,
      output      [6:0]  HEX0,
      output      [6:0]  HEX1,
      output      [6:0]  HEX2,
      output      [6:0]  HEX3,
      output      [6:0]  HEX4,
      output      [6:0]  HEX5,
      input              IRDA_RXD,
      output             IRDA_TXD,
      input       [3:0]  KEY,
      output      [9:0]  LEDR,
      inout              PS2_CLK,
      inout              PS2_CLK2,
      inout              PS2_DAT,
      inout              PS2_DAT2,
      input       [9:0]  SW,
      input              TD_CLK27,
      input      [7:0]   TD_DATA,
      input              TD_HS,
      output             TD_RESET_N,
      input              TD_VS,
      output      [7:0]  VGA_B,
      output             VGA_BLANK_N,
      output             VGA_CLK,
      output      [7:0]  VGA_G,
      output             VGA_HS,
      output      [7:0]  VGA_R,
      output             VGA_SYNC_N,
      output             VGA_VS
);

// ── Unused output tie-offs ────────────────────────────────────────────────────
assign ADC_CONVST    = 1'b0;
assign ADC_DIN       = 1'b0;
assign ADC_SCLK      = 1'b0;
assign AUD_DACDAT    = 1'b0;
assign AUD_XCK       = 1'b0;
assign FPGA_I2C_SCLK = 1'b0;
assign FAN_CTRL      = 1'b0;
assign IRDA_TXD      = 1'b0;
assign TD_RESET_N    = 1'b1;

assign DRAM_ADDR  = 13'b0;
assign DRAM_BA    = 2'b0;
assign DRAM_CAS_N = 1'b1;
assign DRAM_CKE   = 1'b0;
assign DRAM_CLK   = 1'b0;
assign DRAM_CS_N  = 1'b1;
assign DRAM_LDQM  = 1'b1;
assign DRAM_RAS_N = 1'b1;
assign DRAM_UDQM  = 1'b1;
assign DRAM_WE_N  = 1'b1;

assign VGA_B      = 8'b0;
assign VGA_BLANK_N= 1'b0;
assign VGA_CLK    = 1'b0;
assign VGA_G      = 8'b0;
assign VGA_HS     = 1'b0;
assign VGA_R      = 8'b0;
assign VGA_SYNC_N = 1'b0;
assign VGA_VS     = 1'b0;

assign GPIO_1         = 36'hzzzzzzzzz;
assign GPIO_0[27:0]   = 28'hzzzzzzz;  // GPIO_0[35:28] used by keypad

// ── Hex-to-7-segment decoder (active-low segments) ───────────────────────────
function [6:0] h7s;
    input [3:0] x;
    case (x)
        4'h0: h7s = 7'b100_0000;
        4'h1: h7s = 7'b111_1001;
        4'h2: h7s = 7'b010_0100;
        4'h3: h7s = 7'b011_0000;
        4'h4: h7s = 7'b001_1001;
        4'h5: h7s = 7'b001_0010;
        4'h6: h7s = 7'b000_0010;
        4'h7: h7s = 7'b111_1000;
        4'h8: h7s = 7'b000_0000;
        4'h9: h7s = 7'b001_0000;
        4'hA: h7s = 7'b000_1000;
        4'hB: h7s = 7'b000_0011;
        4'hC: h7s = 7'b100_0110;
        4'hD: h7s = 7'b010_0001;
        4'hE: h7s = 7'b000_0110;
        4'hF: h7s = 7'b000_1110;
    endcase
endfunction

// ── Internal signals ──────────────────────────────────────────────────────────
wire        clk1ms;
wire [3:0]  kpad_pass;
wire        kpad_enter;   // active-low: low while key is held

// ── Clock divider (50 MHz → 1 kHz) ───────────────────────────────────────────
clock1 clk1(
    .clk    (CLOCK_50),
    .clk_out(clk1ms)
);

// ── Keypad interface ──────────────────────────────────────────────────────────
keypad_interface kpad1(
    .clk  (clk1ms),
    .rstn (KEY[0]),           // KEY[0] active-low reset
    .cols (GPIO_0[35:32]),
    .rows (GPIO_0[31:28]),
    .pass (kpad_pass),
    .Enter(kpad_enter)
);

// ── Outputs ───────────────────────────────────────────────────────────────────
assign HEX0 = h7s(kpad_pass);   // decoded key value
assign HEX1 = 7'h7F;            // blank
assign HEX2 = 7'h7F;            // blank
assign HEX3 = 7'h7F;            // blank
assign HEX4 = 7'h7F;            // blank
assign HEX5 = 7'h7F;            // blank

assign LEDR[3:0] = kpad_pass;   // key bits
assign LEDR[4]   = ~kpad_enter; // high = key currently detected (Enter active)
assign LEDR[9:5] = 5'b0;

endmodule
