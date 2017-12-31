
`define CL 512
`define MAX_READ 64
`define READ_NUM_WIDTH 6

	parameter Len = 101;
	
	parameter F_init = 	6'b00_0001; // F_init will disable the forward pipeline
	parameter F_run =  	6'b00_0010;
	parameter F_break = 6'b00_0100;
	parameter BCK_INI = 6'b00_1000;	//100
	parameter BCK_RUN = 6'b01_0000;	//101
	parameter BCK_END = 6'b10_0000;	//110
	parameter BUBBLE = 	6'b00_0000;
	
	// parameter F_init = 	6'b00_0000; // F_init will disable the forward pipeline
	// parameter F_run =  	6'b00_0001;
	// parameter F_break = 6'b00_0010;
	// parameter BCK_INI = 6'b00_0100;	//100
	// parameter BCK_RUN = 6'b00_0101;	//101
	// parameter BCK_END = 6'b00_0110;	//110
	// parameter BUBBLE = 	6'b11_0000;