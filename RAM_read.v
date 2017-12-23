
`define READ_NUM_WIDTH 6 
`define MAX_READ 64
`define CL 512
module RAM_read(
	input reset_n,
	input clk,
	input stall,
	
	// part 1: load all reads
	input load_valid,
	input [`CL -1:0] load_data,
	input [`READ_NUM_WIDTH+1 -1:0] batch_size,
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
	
	reg [`CL - 1:0] RAM_read_1[`MAX_READ - 1:0];
	reg [`CL - 1:0] RAM_read_2[`MAX_READ - 1:0];
	reg [`CL - 1:0] RAM_param[`MAX_READ - 1:0];
	reg [`CL - 1:0] RAM_ik[`MAX_READ - 1:0];
	
	reg [`READ_NUM_WIDTH+1 -1:0] curr_position;	
	reg [1:0] arbiter;
	
	wire [`CL-1:0] compress_load_data;
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
					2'b00: RAM_read_1[curr_position] <= compress_load_data;
					2'b01: RAM_read_2[curr_position] <= compress_load_data;
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
		else if(!stall) begin
			if (load_done) begin		
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
	
	wire [`CL-1:0] compress_RAM_read_1_query;
	wire [`CL-1:0] compress_RAM_read_2_query;
	
	always@(posedge clk) begin
		if(!reset_n) begin
			query_position_L1 <= 0;
			select_L1 <= 0;
			status_L1 <= BUBBLE;
		end
		else if(!stall) begin
			// if (status_query != BUBBLE && status_query != F_break && status_query != BCK_END) begin
				case (query_position[6:5])
					2'b00: begin
						select_L1 <= compress_RAM_read_1_query[255:0];
					end
					2'b01: begin
						select_L1 <= compress_RAM_read_1_query[511:256];
					end
					2'b10: begin
						select_L1 <= compress_RAM_read_2_query[255:0];
					end
					2'b11: begin
						select_L1 <= compress_RAM_read_2_query[511:256];
					end
				endcase
				
				query_position_L1 <= query_position;
				status_L1 <= status_query;	
				// end
			// else begin
				// status_L1 <= status_query;		
			// end
		end
	end
	
	//second level extraction 32 -> 8
	always@(posedge clk) begin
		if(!reset_n) begin
			query_position_L2 <= 0;
			select_L2 <= 0;
			status_L2 <= BUBBLE;
		end
		else if(!stall) begin
			if (status_L1 != BUBBLE) begin
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
	end
	
	//third level extraction 8 -> 1
	always@(posedge clk) begin
		if(!reset_n) begin
			new_read_query <= 8'b1111_1111;	
		end
		else if(!stall) begin
			if (status_L2 != BUBBLE) begin
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
	end
	
	assign compress_load_data = {
		6'bxxxxxx,load_data[505:504],
		6'bxxxxxx,load_data[497:496],
		6'bxxxxxx,load_data[489:488],
		6'bxxxxxx,load_data[481:480],
		6'bxxxxxx,load_data[473:472],
		6'bxxxxxx,load_data[465:464],
		6'bxxxxxx,load_data[457:456],
		6'bxxxxxx,load_data[449:448],
		6'bxxxxxx,load_data[441:440],
		6'bxxxxxx,load_data[433:432],
		6'bxxxxxx,load_data[425:424],
		6'bxxxxxx,load_data[417:416],
		6'bxxxxxx,load_data[409:408],
		6'bxxxxxx,load_data[401:400],
		6'bxxxxxx,load_data[393:392],
		6'bxxxxxx,load_data[385:384],
		6'bxxxxxx,load_data[377:376],
		6'bxxxxxx,load_data[369:368],
		6'bxxxxxx,load_data[361:360],
		6'bxxxxxx,load_data[353:352],
		6'bxxxxxx,load_data[345:344],
		6'bxxxxxx,load_data[337:336],
		6'bxxxxxx,load_data[329:328],
		6'bxxxxxx,load_data[321:320],
		6'bxxxxxx,load_data[313:312],
		6'bxxxxxx,load_data[305:304],
		6'bxxxxxx,load_data[297:296],
		6'bxxxxxx,load_data[289:288],
		6'bxxxxxx,load_data[281:280],
		6'bxxxxxx,load_data[273:272],
		6'bxxxxxx,load_data[265:264],
		6'bxxxxxx,load_data[257:256],
		6'bxxxxxx,load_data[249:248],
		6'bxxxxxx,load_data[241:240],
		6'bxxxxxx,load_data[233:232],
		6'bxxxxxx,load_data[225:224],
		6'bxxxxxx,load_data[217:216],
		6'bxxxxxx,load_data[209:208],
		6'bxxxxxx,load_data[201:200],
		6'bxxxxxx,load_data[193:192],
		6'bxxxxxx,load_data[185:184],
		6'bxxxxxx,load_data[177:176],
		6'bxxxxxx,load_data[169:168],
		6'bxxxxxx,load_data[161:160],
		6'bxxxxxx,load_data[153:152],
		6'bxxxxxx,load_data[145:144],
		6'bxxxxxx,load_data[137:136],
		6'bxxxxxx,load_data[129:128],
		6'bxxxxxx,load_data[121:120],
		6'bxxxxxx,load_data[113:112],
		6'bxxxxxx,load_data[105:104],
		6'bxxxxxx,load_data[97:96],
		6'bxxxxxx,load_data[89:88],
		6'bxxxxxx,load_data[81:80],
		6'bxxxxxx,load_data[73:72],
		6'bxxxxxx,load_data[65:64],
		6'bxxxxxx,load_data[57:56],
		6'bxxxxxx,load_data[49:48],
		6'bxxxxxx,load_data[41:40],
		6'bxxxxxx,load_data[33:32],
		6'bxxxxxx,load_data[25:24],
		6'bxxxxxx,load_data[17:16],
		6'bxxxxxx,load_data[9:8],
		6'bxxxxxx,load_data[1:0]
	};
	
	assign compress_RAM_read_1_query = {
		6'b000000,RAM_read_1[query_read_num][505:504],
		6'b000000,RAM_read_1[query_read_num][497:496],
		6'b000000,RAM_read_1[query_read_num][489:488],
		6'b000000,RAM_read_1[query_read_num][481:480],
		6'b000000,RAM_read_1[query_read_num][473:472],
		6'b000000,RAM_read_1[query_read_num][465:464],
		6'b000000,RAM_read_1[query_read_num][457:456],
		6'b000000,RAM_read_1[query_read_num][449:448],
		6'b000000,RAM_read_1[query_read_num][441:440],
		6'b000000,RAM_read_1[query_read_num][433:432],
		6'b000000,RAM_read_1[query_read_num][425:424],
		6'b000000,RAM_read_1[query_read_num][417:416],
		6'b000000,RAM_read_1[query_read_num][409:408],
		6'b000000,RAM_read_1[query_read_num][401:400],
		6'b000000,RAM_read_1[query_read_num][393:392],
		6'b000000,RAM_read_1[query_read_num][385:384],
		6'b000000,RAM_read_1[query_read_num][377:376],
		6'b000000,RAM_read_1[query_read_num][369:368],
		6'b000000,RAM_read_1[query_read_num][361:360],
		6'b000000,RAM_read_1[query_read_num][353:352],
		6'b000000,RAM_read_1[query_read_num][345:344],
		6'b000000,RAM_read_1[query_read_num][337:336],
		6'b000000,RAM_read_1[query_read_num][329:328],
		6'b000000,RAM_read_1[query_read_num][321:320],
		6'b000000,RAM_read_1[query_read_num][313:312],
		6'b000000,RAM_read_1[query_read_num][305:304],
		6'b000000,RAM_read_1[query_read_num][297:296],
		6'b000000,RAM_read_1[query_read_num][289:288],
		6'b000000,RAM_read_1[query_read_num][281:280],
		6'b000000,RAM_read_1[query_read_num][273:272],
		6'b000000,RAM_read_1[query_read_num][265:264],
		6'b000000,RAM_read_1[query_read_num][257:256],
		6'b000000,RAM_read_1[query_read_num][249:248],
		6'b000000,RAM_read_1[query_read_num][241:240],
		6'b000000,RAM_read_1[query_read_num][233:232],
		6'b000000,RAM_read_1[query_read_num][225:224],
		6'b000000,RAM_read_1[query_read_num][217:216],
		6'b000000,RAM_read_1[query_read_num][209:208],
		6'b000000,RAM_read_1[query_read_num][201:200],
		6'b000000,RAM_read_1[query_read_num][193:192],
		6'b000000,RAM_read_1[query_read_num][185:184],
		6'b000000,RAM_read_1[query_read_num][177:176],
		6'b000000,RAM_read_1[query_read_num][169:168],
		6'b000000,RAM_read_1[query_read_num][161:160],
		6'b000000,RAM_read_1[query_read_num][153:152],
		6'b000000,RAM_read_1[query_read_num][145:144],
		6'b000000,RAM_read_1[query_read_num][137:136],
		6'b000000,RAM_read_1[query_read_num][129:128],
		6'b000000,RAM_read_1[query_read_num][121:120],
		6'b000000,RAM_read_1[query_read_num][113:112],
		6'b000000,RAM_read_1[query_read_num][105:104],
		6'b000000,RAM_read_1[query_read_num][97:96],
		6'b000000,RAM_read_1[query_read_num][89:88],
		6'b000000,RAM_read_1[query_read_num][81:80],
		6'b000000,RAM_read_1[query_read_num][73:72],
		6'b000000,RAM_read_1[query_read_num][65:64],
		6'b000000,RAM_read_1[query_read_num][57:56],
		6'b000000,RAM_read_1[query_read_num][49:48],
		6'b000000,RAM_read_1[query_read_num][41:40],
		6'b000000,RAM_read_1[query_read_num][33:32],
		6'b000000,RAM_read_1[query_read_num][25:24],
		6'b000000,RAM_read_1[query_read_num][17:16],
		6'b000000,RAM_read_1[query_read_num][9:8],
		6'b000000,RAM_read_1[query_read_num][1:0]	
	};

	assign compress_RAM_read_2_query = {
		6'b000000,RAM_read_2[query_read_num][505:504],
		6'b000000,RAM_read_2[query_read_num][497:496],
		6'b000000,RAM_read_2[query_read_num][489:488],
		6'b000000,RAM_read_2[query_read_num][481:480],
		6'b000000,RAM_read_2[query_read_num][473:472],
		6'b000000,RAM_read_2[query_read_num][465:464],
		6'b000000,RAM_read_2[query_read_num][457:456],
		6'b000000,RAM_read_2[query_read_num][449:448],
		6'b000000,RAM_read_2[query_read_num][441:440],
		6'b000000,RAM_read_2[query_read_num][433:432],
		6'b000000,RAM_read_2[query_read_num][425:424],
		6'b000000,RAM_read_2[query_read_num][417:416],
		6'b000000,RAM_read_2[query_read_num][409:408],
		6'b000000,RAM_read_2[query_read_num][401:400],
		6'b000000,RAM_read_2[query_read_num][393:392],
		6'b000000,RAM_read_2[query_read_num][385:384],
		6'b000000,RAM_read_2[query_read_num][377:376],
		6'b000000,RAM_read_2[query_read_num][369:368],
		6'b000000,RAM_read_2[query_read_num][361:360],
		6'b000000,RAM_read_2[query_read_num][353:352],
		6'b000000,RAM_read_2[query_read_num][345:344],
		6'b000000,RAM_read_2[query_read_num][337:336],
		6'b000000,RAM_read_2[query_read_num][329:328],
		6'b000000,RAM_read_2[query_read_num][321:320],
		6'b000000,RAM_read_2[query_read_num][313:312],
		6'b000000,RAM_read_2[query_read_num][305:304],
		6'b000000,RAM_read_2[query_read_num][297:296],
		6'b000000,RAM_read_2[query_read_num][289:288],
		6'b000000,RAM_read_2[query_read_num][281:280],
		6'b000000,RAM_read_2[query_read_num][273:272],
		6'b000000,RAM_read_2[query_read_num][265:264],
		6'b000000,RAM_read_2[query_read_num][257:256],
		6'b000000,RAM_read_2[query_read_num][249:248],
		6'b000000,RAM_read_2[query_read_num][241:240],
		6'b000000,RAM_read_2[query_read_num][233:232],
		6'b000000,RAM_read_2[query_read_num][225:224],
		6'b000000,RAM_read_2[query_read_num][217:216],
		6'b000000,RAM_read_2[query_read_num][209:208],
		6'b000000,RAM_read_2[query_read_num][201:200],
		6'b000000,RAM_read_2[query_read_num][193:192],
		6'b000000,RAM_read_2[query_read_num][185:184],
		6'b000000,RAM_read_2[query_read_num][177:176],
		6'b000000,RAM_read_2[query_read_num][169:168],
		6'b000000,RAM_read_2[query_read_num][161:160],
		6'b000000,RAM_read_2[query_read_num][153:152],
		6'b000000,RAM_read_2[query_read_num][145:144],
		6'b000000,RAM_read_2[query_read_num][137:136],
		6'b000000,RAM_read_2[query_read_num][129:128],
		6'b000000,RAM_read_2[query_read_num][121:120],
		6'b000000,RAM_read_2[query_read_num][113:112],
		6'b000000,RAM_read_2[query_read_num][105:104],
		6'b000000,RAM_read_2[query_read_num][97:96],
		6'b000000,RAM_read_2[query_read_num][89:88],
		6'b000000,RAM_read_2[query_read_num][81:80],
		6'b000000,RAM_read_2[query_read_num][73:72],
		6'b000000,RAM_read_2[query_read_num][65:64],
		6'b000000,RAM_read_2[query_read_num][57:56],
		6'b000000,RAM_read_2[query_read_num][49:48],
		6'b000000,RAM_read_2[query_read_num][41:40],
		6'b000000,RAM_read_2[query_read_num][33:32],
		6'b000000,RAM_read_2[query_read_num][25:24],
		6'b000000,RAM_read_2[query_read_num][17:16],
		6'b000000,RAM_read_2[query_read_num][9:8],
		6'b000000,RAM_read_2[query_read_num][1:0]
	
	};
endmodule
