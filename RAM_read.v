
`define READ_NUM_WIDTH 8 
`define MAX_READ 256
module RAM_read(
	input reset_n,
	input clk,
	
	
	// part 1: load all reads
	input load_valid,
	input [511:0] load_data,
	input [8:0] batch_size,
	output reg load_done,
	
	// part 2: provide new read to pipeline
	input new_read, //indicate RAM to update new_read
	
	//output reg new_read_valid,
	output new_read_valid,
	
	output [`READ_NUM_WIDTH - 1:0] new_read_num, //equal to read_num
	output [63:0] new_ik_x0, new_ik_x1, new_ik_x2, new_ik_info,
	output [6:0] new_forward_i, //[important] forward_i points to the position already processed
	output [6:0] new_min_intv,
	
	//part 3: provide new query to queue
	input [5:0] status_query,
	input [6:0] query_position,
	input [`READ_NUM_WIDTH - 1:0] query_read_num,
	output reg [7:0] new_read_query,
	
	//part 4: provide primary,  L2
	output [63:0] primary,
	output [63:0] L2_0, L2_1, L2_2, L2_3
);
	
	parameter F_init = 0; // F_init will disable the forward pipeline
	parameter F_run = 1;
	parameter F_break = 2;
	parameter BCK_INI = 6'h4;	//100
	parameter BCK_RUN = 6'h5;	//101
	parameter BCK_END = 6'h6;	//110
	parameter BUBBLE = 6'b110000;
	parameter DONE = 6'b100000;
	
	parameter CL = 512;
	
	
	reg [CL - 1:0] RAM_read_1[`MAX_READ - 1:0];
	reg [CL - 1:0] RAM_read_2[`MAX_READ - 1:0];
	reg [CL - 1:0] RAM_param[`MAX_READ - 1:0];
	reg [CL - 1:0] RAM_ik[`MAX_READ - 1:0];
	
	reg [8:0] curr_position;	
	reg [1:0] arbiter;
	
	//part 1: load all reads
	always@(posedge clk) begin
		if(!reset_n) begin
			curr_position <= 0;
			arbiter <= 0;
			load_done <= 0;
		end
		else begin
			if (load_valid) begin
				arbiter <= arbiter + 1;
				case(arbiter) 
					2'b00: RAM_read_1[curr_position] <= load_data;
					2'b01: RAM_read_2[curr_position] <= load_data;
					2'b10: RAM_param[curr_position] <= load_data;
					2'b11: begin 
						RAM_ik[curr_position] <= load_data;
						curr_position <= curr_position + 1;
					end				
				endcase			
			end
			
			if (curr_position == batch_size && curr_position > 0) load_done <= 1;
		end
	end
	
	assign primary = RAM_param[0][191:128];
	assign L2_0 = RAM_ik[0][319:256];
	assign L2_1 = RAM_ik[0][383:320];
	assign L2_2 = RAM_ik[0][447:384];
	assign L2_3 = RAM_ik[0][511:448];
	
	//part 2: provide new reads to pipeline
	reg [8:0] new_read_ptr;	
	reg [10:0] param_ptr; 
	reg [10:0] ik_ptr;
	reg [7:0] test_first_query;
	
	assign new_read_num = new_read_valid ? new_read_ptr : 9'b1_1111_1111;
	
	assign new_ik_x0   = new_read_valid ? RAM_ik[new_read_ptr][63:0] : 64'h1111_1111_1111_1111;
	assign new_ik_x1   = new_read_valid ? RAM_ik[new_read_ptr][127:64] : 64'h1111_1111_1111_1111;
	assign new_ik_x2   = new_read_valid ? RAM_ik[new_read_ptr][191:128] : 64'h1111_1111_1111_1111;
	assign new_ik_info = new_read_valid ? RAM_ik[new_read_ptr][255:192] : 64'h1111_1111_1111_1111;
	assign new_forward_i = new_read_valid ? RAM_param[new_read_ptr][6:0] : 7'b111_1111;
	assign new_min_intv = new_read_valid ? RAM_param[new_read_ptr][70:64] : 7'b111_1111;
	
	assign new_read_valid = reset_n & load_done & (new_read_ptr < curr_position) ;
	always@(posedge clk) begin
		if(!reset_n) begin
			new_read_ptr <= 0;
			// new_read_valid <= 0;			
		end
		else if (load_done) begin		
			if(new_read_ptr < curr_position) begin
				// new_read_valid <= 1;
				
				if(new_read) begin
					new_read_ptr <= new_read_ptr + 1;
				end
				else begin
					new_read_ptr <= new_read_ptr;
				end
			end
			else begin
				// new_read_valid <= 0;
				new_read_ptr <= new_read_ptr;
			end
		end
		
		else begin
			// new_read_valid <= 0;
			new_read_ptr <= new_read_ptr;		
		end
	end
	
	//part 3: provide new query to queue	
	wire [8:0] lower = {query_position[5:0],3'b000};
	wire [8:0] upper = {query_position[5:0],3'b111};
	
	reg [255:0] select_L1; //contain 32 querys
	reg [63:0] select_L2;
	
	reg [6:0] query_position_L1;
	reg [6:0] query_position_L2;
	
	reg [5:0] status_L1;
	reg [5:0] status_L2;
	
	//first level extraction 101 -> 32
	always@(posedge clk) begin
		if(!reset_n) begin
			query_position_L1 <= 0;
			select_L1 <= 0;
			status_L1 <= BUBBLE;
		end
		else if (status_query != BUBBLE && status_query != F_break && status_query != BCK_END) begin
			case (query_position[6:5])
				2'b00: begin
					select_L1 <= RAM_read_1[query_read_num][255:0];
				end
				2'b01: begin
					select_L1 <= RAM_read_1[query_read_num][511:256];
				end
				2'b10: begin
					select_L1 <= RAM_read_2[query_read_num][255:0];
				end
				2'b11: begin
					select_L1 <= RAM_read_2[query_read_num][511:256];
				end
			endcase
			
			query_position_L1 <= query_position;
			status_L1 <= status_query;	
		end
		else begin
			status_L1 <= status_query;		
		end
	end
	
	//second level extraction 32 -> 8
	always@(posedge clk) begin
		if(!reset_n) begin
			query_position_L2 <= 0;
			select_L2 <= 0;
			status_L2 <= BUBBLE;
		end
		else if (status_L1 != BUBBLE) begin
			case(query_position_L1[4:3])
				2'b00: begin
					select_L2 <= select_L1[63:0];
				end
				2'b01: begin
					select_L2 <= select_L1[127:64];
				end
				2'b10: begin
					select_L2 <= select_L1[191:128];
				end
				2'b11: begin
					select_L2 <= select_L1[255:192];
				end
			endcase
			
			query_position_L2 <= query_position_L1;
			status_L2 <= status_L1;
		end
		else begin
			query_position_L2 <= 0;
			select_L2 <= 0;
			status_L2 <= status_L1;
		end
	end
	
	//third level extraction 8 -> 1
	always@(posedge clk) begin
		if(!reset_n) begin
			new_read_query <= 8'b1111_1111;	
		end
		else if (status_L2 != BUBBLE) begin
			case(query_position_L2[2:0])
				3'b000: begin
					new_read_query <= select_L2[7:0];
				end
				3'b001: begin
					new_read_query <= select_L2[15:8];
				end
				3'b010: begin
					new_read_query <= select_L2[23:16];
				end
				3'b011: begin
					new_read_query <= select_L2[31:24];
				end
				3'b100: begin
					new_read_query <= select_L2[39:32];
				end
				3'b101: begin
					new_read_query <= select_L2[47:40];
				end
				3'b110: begin
					new_read_query <= select_L2[55:48];
				end
				3'b111: begin
					new_read_query <= select_L2[63:56];
				end
			endcase
		end
		else begin
			new_read_query <= 8'b1111_1111;		
		end
	end

endmodule
