// ============================================================================
// Copyright (c) 2013 by Terasic Technologies Inc.
// ============================================================================
//
// Permission:
//
//   Terasic grants permission to use and modify this code for use
//   in synthesis for all Terasic Development Boards and Altera Development 
//   Kits made by Terasic.  Other use of this code, including the selling 
//   ,duplication, or modification of any portion is strictly prohibited.
//
// Disclaimer:
//
//   This VHDL/Verilog or C/C++ source code is intended as a design reference
//   which illustrates how these types of functions can be implemented.
//   It is the user's responsibility to verify their design for
//   consistency and functionality through the use of formal
//   verification methods.  Terasic provides no warranty regarding the use 
//   or functionality of this code.
//
// ============================================================================
//           
//  Terasic Technologies Inc
//  9F., No.176, Sec.2, Gongdao 5th Rd, East Dist, Hsinchu City, 30070. Taiwan
//  
//  
//                     web: http://www.terasic.com/  
//                     email: support@terasic.com
//
// ============================================================================
//Date:  Thu Jul 11 11:26:45 2013
// ============================================================================

//`define ENABLE_HPS

module DE1_SoC_golden_top(

      ///////// ADC /////////
      output             ADC_CONVST,
      output             ADC_DIN,
      input              ADC_DOUT,
      output             ADC_SCLK,

      ///////// AUD /////////
      input              AUD_ADCDAT,
      inout              AUD_ADCLRCK,
      inout              AUD_BCLK,
      output             AUD_DACDAT,
      inout              AUD_DACLRCK,
      output             AUD_XCK,

      ///////// CLOCK2 /////////
      input              CLOCK2_50,

      ///////// CLOCK3 /////////
      input              CLOCK3_50,

      ///////// CLOCK4 /////////
      input              CLOCK4_50,

      ///////// CLOCK /////////
      input              CLOCK_50,

      ///////// DRAM /////////
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

      ///////// FAN /////////
      output             FAN_CTRL,

      ///////// FPGA /////////
      output             FPGA_I2C_SCLK,
      inout              FPGA_I2C_SDAT,

      ///////// GPIO /////////
      inout     [35:0]         GPIO_0,
      inout     [35:0]         GPIO_1,
 

      ///////// HEX0 /////////
      output      [6:0]  HEX0,

      ///////// HEX1 /////////
      output      [6:0]  HEX1,

      ///////// HEX2 /////////
      output      [6:0]  HEX2,

      ///////// HEX3 /////////
      output      [6:0]  HEX3,

      ///////// HEX4 /////////
      output      [6:0]  HEX4,

      ///////// HEX5 /////////
      output      [6:0]  HEX5,

`ifdef ENABLE_HPS
      ///////// HPS /////////
      inout              HPS_CONV_USB_N,
      output      [14:0] HPS_DDR3_ADDR,
      output      [2:0]  HPS_DDR3_BA,
      output             HPS_DDR3_CAS_N,
      output             HPS_DDR3_CKE,
      output             HPS_DDR3_CK_N,
      output             HPS_DDR3_CK_P,
      output             HPS_DDR3_CS_N,
      output      [3:0]  HPS_DDR3_DM,
      inout       [31:0] HPS_DDR3_DQ,
      inout       [3:0]  HPS_DDR3_DQS_N,
      inout       [3:0]  HPS_DDR3_DQS_P,
      output             HPS_DDR3_ODT,
      output             HPS_DDR3_RAS_N,
      output             HPS_DDR3_RESET_N,
      input              HPS_DDR3_RZQ,
      output             HPS_DDR3_WE_N,
      output             HPS_ENET_GTX_CLK,
      inout              HPS_ENET_INT_N,
      output             HPS_ENET_MDC,
      inout              HPS_ENET_MDIO,
      input              HPS_ENET_RX_CLK,
      input       [3:0]  HPS_ENET_RX_DATA,
      input              HPS_ENET_RX_DV,
      output      [3:0]  HPS_ENET_TX_DATA,
      output             HPS_ENET_TX_EN,
      inout       [3:0]  HPS_FLASH_DATA,
      output             HPS_FLASH_DCLK,
      output             HPS_FLASH_NCSO,
      inout              HPS_GSENSOR_INT,
      inout              HPS_I2C1_SCLK,
      inout              HPS_I2C1_SDAT,
      inout              HPS_I2C2_SCLK,
      inout              HPS_I2C2_SDAT,
      inout              HPS_I2C_CONTROL,
      inout              HPS_KEY,
      inout              HPS_LED,
      inout              HPS_LTC_GPIO,
      output             HPS_SD_CLK,
      inout              HPS_SD_CMD,
      inout       [3:0]  HPS_SD_DATA,
      output             HPS_SPIM_CLK,
      input              HPS_SPIM_MISO,
      output             HPS_SPIM_MOSI,
      inout              HPS_SPIM_SS,
      input              HPS_UART_RX,
      output             HPS_UART_TX,
      input              HPS_USB_CLKOUT,
      inout       [7:0]  HPS_USB_DATA,
      input              HPS_USB_DIR,
      input              HPS_USB_NXT,
      output             HPS_USB_STP,
`endif /*ENABLE_HPS*/

      ///////// IRDA /////////
      input              IRDA_RXD,
      output             IRDA_TXD,

      ///////// KEY /////////
      input       [3:0]  KEY,

      ///////// LEDR /////////
      output      [9:0]  LEDR,

      ///////// PS2 /////////
      inout              PS2_CLK,
      inout              PS2_CLK2,
      inout              PS2_DAT,
      inout              PS2_DAT2,

      ///////// SW /////////
      input       [9:0]  SW,

      ///////// TD /////////
      input              TD_CLK27,
      input      [7:0]  TD_DATA,
      input             TD_HS,
      output             TD_RESET_N,
      input             TD_VS,

      ///////// VGA /////////
      output      [7:0]  VGA_B,
      output             VGA_BLANK_N,
      output             VGA_CLK,
      output      [7:0]  VGA_G,
      output             VGA_HS,
      output      [7:0]  VGA_R,
      output             VGA_SYNC_N,
      output             VGA_VS
);


//=======================================================
//  REG/WIRE declarations
//=======================================================

// Unused output tie-offs (NIOS II removed — lab_2 is the sole design)
assign ADC_CONVST   = 1'b0;
assign ADC_DIN      = 1'b0;
assign ADC_SCLK     = 1'b0;
assign AUD_DACDAT   = 1'b0;
assign AUD_XCK      = 1'b0;
assign FPGA_I2C_SCLK = 1'b0;
assign FAN_CTRL     = 1'b0;
assign IRDA_TXD     = 1'b0;
assign TD_RESET_N   = 1'b1;   // active-low, keep deasserted

// DRAM — deassert all controls so SDRAM stays idle
assign DRAM_ADDR    = 13'b0;
assign DRAM_BA      = 2'b0;
assign DRAM_CAS_N   = 1'b1;
assign DRAM_CKE     = 1'b0;
assign DRAM_CLK     = 1'b0;
assign DRAM_CS_N    = 1'b1;
assign DRAM_LDQM    = 1'b1;
assign DRAM_RAS_N   = 1'b1;
assign DRAM_UDQM    = 1'b1;
assign DRAM_WE_N    = 1'b1;

// HEX displays — blank all (segments active-low, 7'h7F = all off)
assign HEX0 = 7'h7F;
assign HEX1 = 7'h7F;
assign HEX2 = 7'h7F;
assign HEX3 = 7'h7F;
assign HEX4 = 7'h7F;
assign HEX5 = 7'h7F;

// VGA — blank
assign VGA_B       = 8'b0;
assign VGA_BLANK_N = 1'b0;
assign VGA_CLK     = 1'b0;
assign VGA_G       = 8'b0;
assign VGA_HS      = 1'b0;
assign VGA_R       = 8'b0;
assign VGA_SYNC_N  = 1'b0;
assign VGA_VS      = 1'b0;

// LEDR[9:4] — unused by lab_2
assign LEDR[9:4]   = 6'b0;

// GPIO_1 and unused GPIO_0 bits — tri-state
assign GPIO_1      = 36'hzzzzzzzzz;
assign GPIO_0[27:0] = 28'hzzzzzzz;  // GPIO_0[35:28] used by lab_2



//=======================================================
//  Structural coding
//=======================================================

	// ── Lab 2 — Digital Access Control System ───────────────────────────────
	// Keypad 4×4 matrix: columns on GPIO_0[35:32], rows on GPIO_0[31:28]
	// KEY[0] = resetN (active-low), KEY[1] = supervisor key, KEY[2] = srst_access
	// LEDR[0]=error  LEDR[1]=correct  LEDR[2]=Err_LED  LEDR[3]=Corr_LED
	// KEY buttons are active-low on DE1-SoC:
	//   KEY[0] → resetN  (active-low, connected directly — polarity matches)
	//   KEY[1] → key     (active-high in design, invert KEY[1])
	//   KEY[2] → srst_access (active-high in design, invert KEY[2])
	lab_2 u_lab2 (
		.clk         (CLOCK_50),
		.resetN      (KEY[0]),
		.key         (~KEY[1]),
		.srst_access (~KEY[2]),
		.cols        (GPIO_0[35:32]),
		.rows        (GPIO_0[31:28]),
		.error       (LEDR[0]),
		.correct     (LEDR[1]),
		.Err_LED     (LEDR[2]),
		.Corr_LED    (LEDR[3])
	);



endmodule
