
`define READ_NUM_WIDTH 8
//for test purpose 
`define MAX_READ 256 

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
	output reg [255:0] curr_q_2,
	
	//--------------------------------
	
	// mem queue, port A
	input [`READ_NUM_WIDTH - 1:0] mem_read_num_1,
	input mem_we_1,
	input [255:0] mem_data_1, //[important]sequence: [p_info, p_x2, p_x1, p_x0]
	input [6:0] mem_addr_1,
	output reg [255:0] mem_q_1,
	
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

	//valid bits
	//ik_x0 = 33; ik_x1 = 33; ik_x2 = 33; ik_info = 14;
	//33+33+33+14 = 113 bits
	
	//512 reads * 2 queue/read * 101 slots / queue * 113 bits/slots = 1.7M
	reg [112:0] curr_queue [`MAX_READ - 1:0][100:0];
	reg [112:0] mem_queue  [`MAX_READ - 1:0][100:0];
	reg [6:0] mem_size_queue[`MAX_READ - 1:0]; //mem_size = 7bits;
	reg [6:0] ret_queue[`MAX_READ - 1:0] ; //ret = 7 bits;
	
	//curr queue
	always@(posedge clk) begin
		
		//port A
		if(curr_we_1) begin
			curr_queue[curr_read_num_1][curr_addr_1] <= {curr_data_1[230:224],curr_data_1[198:192],curr_data_1[160:128],curr_data_1[96:64],curr_data_1[32:0]};
			//curr_q_1 <= curr_data_1;
		end
		
		//[very important] use stall signal as the read_en. 
		if(!stall) begin
			{curr_q_2[230:224],curr_q_2[198:192],curr_q_2[160:128],curr_q_2[96: 64],curr_q_2[32: 0]} <= curr_queue[curr_read_num_2][curr_addr_2];
			{curr_q_2[255:231],curr_q_2[223:199],curr_q_2[191:161],curr_q_2[127:97],curr_q_2[63:33]} <= 0;
		end
	end
	
	//mem queue
	always@(posedge clk) begin
			//port A
			if(mem_we_1) begin
				mem_queue[mem_read_num_1][mem_addr_1] <= {mem_data_1[230:224],mem_data_1[198:192],mem_data_1[160:128],mem_data_1[96:64],mem_data_1[32:0]};
				//mem_q_1 <= mem_data_1;
			end
			
			if(!stall) begin
				{mem_q_1[230:224],mem_q_1[198:192],mem_q_1[160:128],mem_q_1[96:64],mem_q_1[32:0]} <= mem_queue[mem_read_num_1][mem_addr_1];
				{mem_q_1[255:231],mem_q_1[223:199],mem_q_1[191:161],mem_q_1[127:97],mem_q_1[63:33]} <= 0;
			end
	end
	
	//params
	reg [`READ_NUM_WIDTH+1 - 1:0] done_counter;
	reg all_read_done;
	
	always@(posedge clk) begin
		if(!reset_n) begin
			done_counter <= 0;
			all_read_done <= 0;
		end
		else begin
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
	
	//output module
	
	always@(posedge clk) begin
		if(!reset_n) begin
			output_request <= 0;
		end
		else if(all_read_done)begin
			output_request <= 1;
		end
		else begin
			output_request <= 0;
		end
	end
	
	reg [`READ_NUM_WIDTH+1 - 1:0] output_result_ptr;
	reg [6:0] output_mem_ptr;
	reg [6:0] curr_size;//mem size, not read size
	reg [6:0] already_output_num; //mem number, not read number
	reg group_start; //indicate the initial of a read's data
	
	always@(posedge clk) begin
		if(!reset_n) begin
			output_result_ptr <= 0;
			output_mem_ptr <= 0;
			group_start <= 1;
			output_valid <= 0;
			output_data <= 0;
			output_finish <= 0;
			already_output_num <= 0;
			curr_size <= 0;
		end
		else if(output_permit) begin
			if(!stall) begin
				if(output_result_ptr < batch_size) begin 
					if(group_start) begin
						output_valid		 <= 1;
						output_data[9:0]     <= output_result_ptr; //read num
						output_data[63:10]   <= 0;
						output_data[70:64]   <= mem_size_queue[output_result_ptr];
						output_data[127:71]  <= 0;
						output_data[159:128] <= {25'b0, ret_queue[output_result_ptr]};
						output_data[511:160] <= 0;
						group_start <= 0;
						curr_size <= mem_size_queue[output_result_ptr];
						already_output_num <= 0;
					end
					else if(already_output_num < curr_size - 1) begin
						output_valid <= 1;
						
						{output_data[230:224],output_data[198:192],output_data[160:128],output_data[96:64],output_data[32:0]} <= mem_queue[output_result_ptr][already_output_num];
						{output_data[255:231],output_data[223:199],output_data[191:161],output_data[127:97],output_data[63:33]} <= 0;
						
						{output_data[486:480],output_data[454:448],output_data[416:384],output_data[352:320],output_data[288:256]} <= mem_queue[output_result_ptr][already_output_num + 1];
						{output_data[511:487],output_data[479:455],output_data[447:417],output_data[383:353],output_data[319:289]} <= 0;
						already_output_num <= already_output_num + 2;	
					end
					else if(already_output_num == curr_size - 1) begin
						output_valid <= 1;
						
						{output_data[230:224],output_data[198:192],output_data[160:128],output_data[96:64],output_data[32:0]} <= mem_queue[output_result_ptr][already_output_num];
						{output_data[255:231],output_data[223:199],output_data[191:161],output_data[127:97],output_data[63:33]} <= 0;
						output_data[511:256] <= 0;
						
						already_output_num <= already_output_num + 1;
					end
					else if(already_output_num == curr_size) begin
						output_valid <= 0; //[important] during the output process there will be a gap between each mem group!
						output_result_ptr <= output_result_ptr + 1;
						group_start <= 1;
					end
				end
				else begin
					output_valid <= 0;
					output_finish <= 1;
				
				end
			end
			else begin
				output_valid <= 0;
			end
		end
	end
	
endmodule	