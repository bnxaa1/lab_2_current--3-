module codeStorage (input logic clk, wren, rst_codeNum, clk_en,
							input logic [5:0] rStartingAddress, wStartingAddress,
							input logic [3:0]  dataIn,
							output logic done,
							output logic [3:0]  dataOut);

		logic [5:0] rdaddress, wraddress;
		logic [3:0] ctr;
		assign done = (ctr == 4'b1001); // done when the code entered reach max = 9 digits
		assign rdaddress = rStartingAddress + {2'b00, ctr}; // enable the ctr for 1 cycle
		assign wraddress = wStartingAddress + {2'b00, ctr};
		ram Ram_Mem(.clock(clk),.data(dataIn),.rdaddress(rdaddress),.wraddress(wraddress),.wren(wren),.q(dataOut));
		counter c2(.clock(clk), .sclr(rst_codeNum), .q(ctr), .cnt_en(clk_en));
		
endmodule


//temporary memory to store the new password before verification
//the new password should be entered twice for validation
//max 10 digits password --> exceeding? red led alert + uart error message
//min 4 digits
//exit without modifying the password
//store the number of digits in a register
//or store 1010 to indicate end (favorable)
//either move the password after checking to the corresponding location
// or move the pointer to the temporary memory
