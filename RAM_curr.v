`define CL 512
`define MAX_READ 512
`define READ_NUM_WIDTH 9
`define CURR_QUEUE_ADDR_WIDTH 16
`define MEM_QUEUE_ADDR_WIDTH 16
`define READ_MAX_MEM 30
`define READ_MAX_CURR 101

module RAM_curr_mem(
	input reset_n,
	input clk,
	input stall,
	input [`READ_NUM_WIDTH+1 - 1:0] batch_size,
	
	// curr queue, port A
	input [`READ_NUM_WIDTH - 1:0] curr_read_num_1,
	input curr_we_1,
	input [255:0] curr_data_1, //[important]sequence: [ik_info, ik_x2, ik_x1, ik_x0]
	input [6:0] curr_addr_1,
	
	//read port B
	input [`READ_NUM_WIDTH - 1:0] curr_read_num_2,
	input [6:0] curr_addr_2,
	output [255:0] curr_q_2,
	
	//--------------------------------
	
	// mem queue, port A
	input [`READ_NUM_WIDTH - 1:0] mem_read_num_1,
	input mem_we_1,
	input [255:0] mem_data_1, //[important]sequence: [p_info, p_x2, p_x1, p_x0]
	input [6:0] mem_addr_1,
	
	//---------------------------------
	
	//mem size
	input mem_size_valid,
	input[6:0] mem_size,
	input[`READ_NUM_WIDTH - 1:0] mem_size_read_num,
	
	//ret
	input ret_valid,
	input [6:0] ret,
	input [`READ_NUM_WIDTH - 1:0] ret_read_num,
	
	//---------------------------------
	
	//output module
	output reg output_request,
	input output_permit,
	output reg [511:0] output_data,
	output reg output_valid,
	output reg output_finish

);
	parameter Len = 101;
	
	parameter F_init = 	6'b00_0001; // F_init will disable the forward pipeline
	parameter F_run =  	6'b00_0010;
	parameter F_break = 6'b00_0100;
	parameter BCK_INI = 6'b00_1000;	//100
	parameter BCK_RUN = 6'b01_0000;	//101
	parameter BCK_END = 6'b10_0000;	//110
	parameter BUBBLE = 	6'b00_0000;
	//valid bits
	//ik_x0 = 33; ik_x1 = 33; ik_x2 = 33; ik_info = 14;
	//33+33+33+14 = 113 bits
	
	//512 reads * 2 queue/read * 101 slots / queue * 113 bits/slots = 1.7M
	reg [6:0] mem_size_queue[`MAX_READ - 1:0]; //mem_size = 7bits;
	reg [6:0] ret_queue[`MAX_READ - 1:0] ; //ret = 7 bits;
	
	wire [`CURR_QUEUE_ADDR_WIDTH-1 : 0] curr_addr_A =  curr_read_num_1 * `READ_MAX_CURR + curr_addr_1;
	wire [`CURR_QUEUE_ADDR_WIDTH-1 : 0] curr_addr_B =  curr_read_num_2 * `READ_MAX_CURR + curr_addr_2;
	wire [112:0] curr_data_A = {curr_data_1[230:224],curr_data_1[198:192],curr_data_1[160:128],curr_data_1[96:64],curr_data_1[32:0]};
	
	//add one pipeline stage for RAM write
	reg curr_we_1_q, curr_we_1_qq;
	reg [`CURR_QUEUE_ADDR_WIDTH-1 : 0] curr_addr_A_q, curr_addr_A_qq, curr_addr_B_q;
	reg [112:0] curr_data_A_q, curr_data_A_qq;
	
	always@(posedge clk) begin
		if(!stall) begin
			curr_we_1_q <= curr_we_1;
			curr_addr_A_q <= curr_addr_A;
			curr_data_A_q <= curr_data_A;
			
			curr_we_1_qq <= curr_we_1_q;
			curr_addr_A_qq <= curr_addr_A_q;
			curr_data_A_qq <= curr_data_A_q;
			
			curr_addr_B_q <= curr_addr_B;
		end
	end
	
	RAM_Curr_Queue curr_queue(
		.clk(clk),
		
		.curr_we_1(curr_we_1_qq),
		.addr_1(curr_addr_A_qq),
		.data(curr_data_A_qq),
		
		.read_en(!stall),
		.addr_2(curr_addr_B_q),
		.q({curr_q_2[230:224],curr_q_2[198:192],curr_q_2[160:128],curr_q_2[96: 64],curr_q_2[32: 0]})
	);
	assign {curr_q_2[255:231],curr_q_2[223:199],curr_q_2[191:161],curr_q_2[127:97],curr_q_2[63:33]} = 0;
	
	
	wire [`MEM_QUEUE_ADDR_WIDTH-1 : 0] mem_addr_A = (mem_read_num_1 * `READ_MAX_MEM + mem_addr_1);
	wire [112:0] mem_data_A = {mem_data_1[230:224],mem_data_1[198:192],mem_data_1[160:128],mem_data_1[96:64],mem_data_1[32:0]};
	reg [`READ_NUM_WIDTH+1 - 1:0] output_result_ptr;

	
	//add one pipeline stage for mem write
	reg mem_we_1_q, mem_we_1_qq_0, mem_we_1_qq_1, mem_we_1_qq_2, mem_we_1_qq_3;
	reg [112:0] mem_data_A_q, mem_data_A_qq;
	reg [112:0] mem_data_A_qq_0, mem_data_A_qq_1, mem_data_A_qq_2, mem_data_A_qq_3;
	
	always@(posedge clk) begin
		if(!stall) begin
			mem_we_1_q <= mem_we_1;
			mem_we_1_qq_0 <= mem_we_1_q;
			mem_we_1_qq_1 <= mem_we_1_q;
			mem_we_1_qq_2 <= mem_we_1_q;
			mem_we_1_qq_3 <= mem_we_1_q;
			mem_data_A_q <= mem_data_A;
			mem_data_A_qq_0 <= mem_data_A_q;
			mem_data_A_qq_1 <= mem_data_A_q;
			mem_data_A_qq_2 <= mem_data_A_q;
			mem_data_A_qq_3 <= mem_data_A_q;
		end
	end
	
	reg [6:0] already_output_num, already_output_num_q, already_output_num_qq, already_output_num_qqq, already_output_num_qqqq;
	wire [`MEM_QUEUE_ADDR_WIDTH-1 : 0] mem_addr_A_out = (output_result_ptr * `READ_MAX_MEM + already_output_num);
	wire [`MEM_QUEUE_ADDR_WIDTH-1 : 0] mem_addr_B_out = (output_result_ptr * `READ_MAX_MEM + already_output_num + 1);
	
	reg [`MEM_QUEUE_ADDR_WIDTH-1 : 0] mem_addr_A_out_q, mem_addr_B_out_q, mem_addr_B_out_qqq;
	reg [`MEM_QUEUE_ADDR_WIDTH-1 : 0] mem_addr_B_out_qq_0, mem_addr_B_out_qq_1, mem_addr_B_out_qq_2, mem_addr_B_out_qq_3;
	always@(posedge clk) begin
		if(!stall) begin
			mem_addr_B_out_q <= mem_addr_B_out;
			mem_addr_B_out_qq_0 <= mem_addr_B_out_q;
			mem_addr_B_out_qq_1 <= mem_addr_B_out_q;
			mem_addr_B_out_qq_2 <= mem_addr_B_out_q;
			mem_addr_B_out_qq_3 <= mem_addr_B_out_q;
			mem_addr_B_out_qqq <= mem_addr_B_out_qq_0;
		end
	end
	
	wire [`MEM_QUEUE_ADDR_WIDTH-1 : 0] mem_addr_A_MUX = mem_we_1? mem_addr_A: mem_addr_A_out;
	reg  [`MEM_QUEUE_ADDR_WIDTH-1 : 0] mem_addr_A_MUX_q, mem_addr_A_MUX_qqq;
	reg  [`MEM_QUEUE_ADDR_WIDTH-1 : 0] mem_addr_A_MUX_qq_0, mem_addr_A_MUX_qq_1, mem_addr_A_MUX_qq_2, mem_addr_A_MUX_qq_3;
	always@(posedge clk) begin
		if(!stall) begin
			mem_addr_A_MUX_q <= mem_addr_A_MUX;
			mem_addr_A_MUX_qq_0 <= mem_addr_A_MUX_q;
			mem_addr_A_MUX_qq_1 <= mem_addr_A_MUX_q;
			mem_addr_A_MUX_qq_2 <= mem_addr_A_MUX_q;
			mem_addr_A_MUX_qq_3 <= mem_addr_A_MUX_q;
			mem_addr_A_MUX_qqq <= mem_addr_A_MUX_qq_0;
		end
	end
	
	wire [112:0] mem_q_out_A_0, mem_q_out_B_0;
	wire [112:0] mem_q_out_A_1, mem_q_out_B_1;
	wire [112:0] mem_q_out_A_2, mem_q_out_B_2;
	wire [112:0] mem_q_out_A_3, mem_q_out_B_3;

	
	RAM_Mem_Queue mem_queue_0(
		.clk(clk),
		.read_en(!stall),
		
		.mem_we_1(mem_we_1_qq_0),
		.addr_1(mem_addr_A_MUX_qq_0[`MEM_QUEUE_ADDR_WIDTH-1-2 : 0]),
		.data_1(mem_data_A_qq_0),
		.q_1(mem_q_out_A_0),
		
		.mem_we_2(1'b0),
		.addr_2(mem_addr_B_out_qq_0[`MEM_QUEUE_ADDR_WIDTH-1-2 : 0]),
		.data_2(113'b0),
		.q_2(mem_q_out_B_0)
	);
	
	RAM_Mem_Queue mem_queue_1(
		.clk(clk),
		.read_en(!stall),
		
		.mem_we_1(mem_we_1_qq_1),
		.addr_1(mem_addr_A_MUX_qq_1[`MEM_QUEUE_ADDR_WIDTH-1-2 : 0]),
		.data_1(mem_data_A_qq_1),
		.q_1(mem_q_out_A_1),
		
		.mem_we_2(1'b0),
		.addr_2(mem_addr_B_out_qq_1[`MEM_QUEUE_ADDR_WIDTH-1-2 : 0]),
		.data_2(113'b0),
		.q_2(mem_q_out_B_1)
	);
	
	RAM_Mem_Queue mem_queue_2(
		.clk(clk),
		.read_en(!stall),
		
		.mem_we_1(mem_we_1_qq_2),
		.addr_1(mem_addr_A_MUX_qq_2[`MEM_QUEUE_ADDR_WIDTH-1-2 : 0]),
		.data_1(mem_data_A_qq_2),
		.q_1(mem_q_out_A_2),
		
		.mem_we_2(1'b0),
		.addr_2(mem_addr_B_out_qq_2[`MEM_QUEUE_ADDR_WIDTH-1-2 : 0]),
		.data_2(113'b0),
		.q_2(mem_q_out_B_2)
	);
	
	RAM_Mem_Queue mem_queue_3(
		.clk(clk),
		.read_en(!stall),
		
		.mem_we_1(mem_we_1_qq_3),
		.addr_1(mem_addr_A_MUX_qq_3[`MEM_QUEUE_ADDR_WIDTH-1-2 : 0]),
		.data_1(mem_data_A_qq_3),
		.q_1(mem_q_out_A_3),
		
		.mem_we_2(1'b0),
		.addr_2(mem_addr_B_out_qq_3[`MEM_QUEUE_ADDR_WIDTH-1-2 : 0]),
		.data_2(113'b0),
		.q_2(mem_q_out_B_3)
	);
	

	
	//params
	reg [`READ_NUM_WIDTH+1 - 1:0] done_counter;
	reg all_read_done;
	
	always@(posedge clk) begin
		if(!reset_n) begin
			done_counter <= 0;
			all_read_done <= 0;
		end
		else begin
			if(!stall) begin
				if(mem_size_valid) begin
					mem_size_queue[mem_size_read_num] <= mem_size;
					done_counter <= done_counter + 1;
				end
				
				if(done_counter == batch_size && done_counter > 0) begin
					all_read_done <= 1;
				end
				else begin
					all_read_done <= 0;
				end
				
				if(ret_valid) begin
					ret_queue[ret_read_num] <= ret;
				end
			end
		end
	end
	
	//output module
	
	always@(posedge clk) begin
		if(!reset_n) begin
			output_request <= 0;
		end
		else if(!stall) begin
			if(all_read_done)begin
				output_request <= 1;
			end
			else begin
				output_request <= 0;
			end
		end
	end
	
	
	reg [6:0] output_mem_ptr;
	reg [6:0] curr_size, curr_size_q, curr_size_qq, curr_size_qqq, curr_size_qqqq;//mem size, not read size
	
	reg group_start, group_start_q, group_start_qq, group_start_qqq, group_start_qqqq;
	
	 //mem number, not read number
	reg [112:0] mem_q_out_A_q, mem_q_out_B_q;
	reg [`READ_NUM_WIDTH+1 - 1:0] output_result_ptr_q, output_result_ptr_qq, output_result_ptr_qqq, output_result_ptr_qqqq;
	
	reg [6:0] mem_size_qqqq;
	reg [6:0] ret_size_qqqq;
	
	always@(posedge clk) begin
		if(!stall) begin
			output_result_ptr_qqqq <= output_result_ptr_qqq;
			output_result_ptr_qqq <= output_result_ptr_qq;
			output_result_ptr_qq <= output_result_ptr_q;
			output_result_ptr_q <= output_result_ptr;
			
			group_start_q <= group_start;
			group_start_qq <= group_start_q;
			group_start_qqq <= group_start_qq;
			group_start_qqqq <= group_start_qqq;
			
			already_output_num_q <= already_output_num;
			already_output_num_qq <= already_output_num_q;
			already_output_num_qqq <= already_output_num_qq;
			already_output_num_qqqq <= already_output_num_qqq;
			
			case(mem_addr_A_MUX_qqq[`MEM_QUEUE_ADDR_WIDTH-1: `MEM_QUEUE_ADDR_WIDTH-2])
				0: mem_q_out_A_q <= mem_q_out_A_0;
				1: mem_q_out_A_q <= mem_q_out_A_1;
				2: mem_q_out_A_q <= mem_q_out_A_2;
				3: mem_q_out_A_q <= mem_q_out_A_3;
			endcase
			
			case(mem_addr_B_out_qqq[`MEM_QUEUE_ADDR_WIDTH-1: `MEM_QUEUE_ADDR_WIDTH-2])
				0: mem_q_out_B_q <= mem_q_out_B_0;
				1: mem_q_out_B_q <= mem_q_out_B_1;
				2: mem_q_out_B_q <= mem_q_out_B_2;
				3: mem_q_out_B_q <= mem_q_out_B_3;
			endcase
			
			mem_size_qqqq <= mem_size_queue[output_result_ptr_qqq];
			ret_size_qqqq <= ret_queue[output_result_ptr_qqq];
			
			curr_size_q <= curr_size;
			curr_size_qq <= curr_size_q;
			curr_size_qqq <= curr_size_qq;
			curr_size_qqqq <= curr_size_qqq;
		end
	end
	
	always@(posedge clk) begin
		if(!stall) begin
			if(group_start_qqqq) begin
				output_data[9:0]     <= output_result_ptr_qqqq; //read num
				output_data[63:10]   <= 0;
				output_data[70:64]   <= mem_size_qqqq;
				output_data[127:71]  <= 0;
				output_data[159:128] <= {25'b0, ret_size_qqqq};
				output_data[511:160] <= 0;
			end
			else if(already_output_num_qqqq < curr_size_qqqq - 1) begin
				{output_data[230:224],output_data[198:192],output_data[160:128],output_data[96:64],output_data[32:0]} <= mem_q_out_A_q;
				{output_data[255:231],output_data[223:199],output_data[191:161],output_data[127:97],output_data[63:33]} <= 0;
				
				{output_data[486:480],output_data[454:448],output_data[416:384],output_data[352:320],output_data[288:256]} <= mem_q_out_B_q;
				{output_data[511:487],output_data[479:455],output_data[447:417],output_data[383:353],output_data[319:289]} <= 0;
			end
			else if(already_output_num_qqqq == curr_size_qqqq - 1) begin
				{output_data[230:224],output_data[198:192],output_data[160:128],output_data[96:64],output_data[32:0]} <= mem_q_out_A_q;
				{output_data[255:231],output_data[223:199],output_data[191:161],output_data[127:97],output_data[63:33]} <= 0;
				
				{output_data[486:480],output_data[454:448],output_data[416:384],output_data[352:320],output_data[288:256]} <= 0;
				{output_data[511:487],output_data[479:455],output_data[447:417],output_data[383:353],output_data[319:289]} <= 0;
			end
			else begin
				output_data <= 0;
			
			end
		end
	end
	
	reg output_valid_d, output_valid_dd, output_valid_ddd, output_valid_dddd;
	reg output_finish_d, output_finish_dd, output_finish_ddd, output_finish_dddd;
	//add one pipeline stage for output_valid and output_finish;
	always@(posedge clk) begin
		if(!stall) begin
			output_valid <= output_valid_dddd;
			output_valid_dddd <= output_valid_ddd;
			output_valid_ddd <= output_valid_dd;
			output_valid_dd <= output_valid_d;
			
			output_finish <= output_finish_dddd;
			output_finish_dddd <= output_finish_ddd;
			output_finish_ddd <= output_finish_dd;				
			output_finish_dd <= output_finish_d;
		end
	end
	
	always@(posedge clk) begin
		if(!stall) begin

		end
	end
	
	always@(posedge clk) begin
		if(!reset_n) begin
			output_result_ptr <= 0;
			output_mem_ptr <= 0;
			group_start <= 1;
			output_valid_d <= 0;
			// output_data <= 0;
			output_finish_d <= 0;
			already_output_num <= 0;
			curr_size <= 0;

		end
		else if(output_permit) begin
			if(!stall) begin
				if(output_result_ptr < batch_size) begin 
					if(group_start) begin
						output_valid_d		 <= 1;

						group_start <= 0;
						curr_size <= mem_size_queue[output_result_ptr];
						already_output_num <= 0;
					end
					else if(already_output_num < curr_size - 1) begin

						already_output_num <= already_output_num + 2;
					
					end
					else if(already_output_num == curr_size - 1) begin				
						
						already_output_num <= already_output_num + 1;						
					
					end
					else if(already_output_num == curr_size) begin
						output_valid_d <= 0; //[important] during the output process there will be a gap between each mem group!
						output_result_ptr <= output_result_ptr + 1;
						group_start <= 1;
					end
				end
				else begin
					output_valid_d <= 0;
					output_finish_d <= 1;
				
				end
			end
		end
	end
	
endmodule	

module RAM_Curr_Queue(
	input clk,
	
	input curr_we_1,
	input [`CURR_QUEUE_ADDR_WIDTH-1 : 0] addr_1,
	input [112:0] data,
	
	input read_en,
	input [`CURR_QUEUE_ADDR_WIDTH-1 : 0] addr_2,
	output reg [112:0] q

);
	reg [112:0] curr_queue [`MAX_READ*`READ_MAX_CURR - 1:0];
	
	always@(posedge clk) begin
		
		//port A
		if(curr_we_1 & read_en) begin
			curr_queue[addr_1] <= data;
		end
		
		//[very important] use stall signal as the read_en. 
		if(read_en) begin
			q <= curr_queue[addr_2];
		end
	end
endmodule

module RAM_Mem_Queue(
	input clk,
	input read_en,
	input mem_we_1,
	input [`MEM_QUEUE_ADDR_WIDTH-1 -2: 0] addr_1,
	input [112:0] data_1,
	output reg [112:0] q_1,
	
	input mem_we_2,
	input [`MEM_QUEUE_ADDR_WIDTH-1 -2: 0] addr_2,
	input [112:0] data_2,
	output reg [112:0] q_2
);
	reg [112:0] mem_queue  [`MAX_READ*`READ_MAX_MEM - 1:0];
	
	always@(posedge clk) begin
		if(mem_we_1 & read_en) begin
			mem_queue[addr_1] <= data_1;
		end
		if(read_en) begin
			q_1 <= mem_queue[addr_1];
		end
		
		if(mem_we_2 & read_en) begin
			mem_queue[addr_2] <= data_2;
		end
		if(read_en) begin
			q_2 <= mem_queue[addr_2];
		end
	end

endmodule