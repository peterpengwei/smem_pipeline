module RAM_curr_mem(
	input reset_n,
	input clk,
	input stall,
	input [8:0] batch_size,
	
	// curr queue, port A
	input [9:0] curr_read_num_1,
	input curr_we_1,
	input [255:0] curr_data_1, //[important]sequence: [ik_info, ik_x2, ik_x1, ik_x0]
	input [6:0] curr_addr_1,
	output reg [255:0] curr_q_1,
	
	//curr queue, port B
	input [9:0] curr_read_num_2,
	input curr_we_2,
	input [255:0] curr_data_2,
	input [6:0] curr_addr_2,
	output reg [255:0] curr_q_2,
	
	//--------------------------------
	
	// mem queue, port A
	input [9:0] mem_read_num_1,
	input mem_we_1,
	input [255:0] mem_data_1, //[important]sequence: [p_info, p_x2, p_x1, p_x0]
	input [6:0] mem_addr_1,
	output reg [255:0] mem_q_1,
	
	//mem queue, port B
	input [9:0] mem_read_num_2,
	input mem_we_2,
	input [255:0] mem_data_2,
	input [6:0] mem_addr_2,
	output reg [255:0] mem_q_2,
	
	//---------------------------------
	
	//mem size
	input mem_size_valid,
	input[6:0] mem_size,
	input[9:0] mem_size_read_num,
	
	//ret
	input ret_valid,
	input[31:0] ret,
	input [9:0] ret_read_num,
	
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
	reg [511:0] curr_queue [100:0][112:0];
	reg [511:0] mem_queue  [100:0][112:0];
	reg [511:0] mem_size_queue[6:0]; //mem_size = 7bits;
	reg [511:0] ret_queue[31:0]; //ret = 32 bits;
	
	//curr queue
	always@(posedge clk) begin
		//port A
		if(curr_we_1) begin
			curr_queue[curr_read_num_1][curr_addr_1] <= {curr_data_1[230:224],curr_data_1[198:192],curr_data_1[160:128],curr_data_1[96:64],curr_data_1[32:0]};
			curr_q_1 <= curr_data_1;
		end
		else begin
			{curr_q_1[230:224],curr_q_1[198:192],curr_q_1[160:128],curr_q_1[96: 64],curr_q_1[32: 0]} <= curr_queue[curr_read_num_1][curr_addr_1];
			{curr_q_1[255:231],curr_q_1[223:199],curr_q_1[191:161],curr_q_1[127:97],curr_q_1[63:33]} <= 0;
		end
		
		//port B
		if(curr_we_2) begin
			curr_queue[curr_read_num_2][curr_addr_2] <= {curr_data_2[230:224],curr_data_2[198:192],curr_data_2[160:128],curr_data_2[96:64],curr_data_2[32:0]};
			curr_q_2 <= curr_data_2;
		end
		else begin
			{curr_q_2[230:224],curr_q_2[198:192],curr_q_2[160:128],curr_q_2[96: 64],curr_q_2[32: 0]} <= curr_queue[curr_read_num_2][curr_addr_2];
			{curr_q_2[255:231],curr_q_2[223:199],curr_q_2[191:161],curr_q_2[127:97],curr_q_2[63:33]} <= 0;
		end
	end
	
	//mem queue
	always@(posedge clk) begin
		//port A
		if(mem_we_1) begin
			mem_queue[mem_read_num_1][mem_addr_1] <= {mem_data_1[230:224],mem_data_1[198:192],mem_data_1[160:128],mem_data_1[96:64],mem_data_1[32:0]};
			mem_q_1 <= mem_data_1;
		end
		else begin
			{mem_q_1[230:224],mem_q_1[198:192],mem_q_1[160:128],mem_q_1[96:64],mem_q_1[32:0]} <= mem_queue[mem_read_num_1][mem_addr_1];
			{mem_q_1[255:231],mem_q_1[223:199],mem_q_1[191:161],mem_q_1[127:97],mem_q_1[63:33]} <= 0;
		end
		
		//port B
		if(mem_we_2) begin
			mem_queue[mem_read_num_2][mem_addr_2] <= {mem_data_2[230:224],mem_data_2[198:192],mem_data_2[160:128],mem_data_2[96:64],mem_data_2[32:0]};
			mem_q_2 <= mem_data_2;
		end
		else begin
			{mem_q_2[230:224],mem_q_2[198:192],mem_q_2[160:128],mem_q_2[96:64],mem_q_2[32:0]} <= mem_queue[mem_read_num_2][mem_addr_2];
			{mem_q_2[255:231],mem_q_2[223:199],mem_q_2[191:161],mem_q_2[127:97],mem_q_2[63:33]} <= 0;
		end
	end
	
	//params
	reg [8:0] done_counter;
	reg all_read_done;
	
	always@(posedge clk) begin
		if(reset_n) begin
			done_counter <= 0;
		end
		else begin
			if(mem_size_valid) begin
				mem_size_queue[mem_size_read_num] <= mem_size;
				done_counter <= done_counter + 1;
			end
			
			if(done_counter == batch_size && done_counter > 0) begin
				all_read_done <= 1;
			end
			
			if(ret_valid) begin
				ret_queue[ret_read_num] <= ret;
			end
			
		end
	end
	
	//output module
	
	always@(posedge clk) begin
		if(reset_n) begin
			output_request <= 0;
		end
		else if(all_read_done)begin
			output_request <= 1;
		end
	end
	
	reg [8:0] output_result_ptr;
	reg [6:0] output_mem_ptr;
	reg [6:0] curr_size;
	reg [6:0] already_output_num;
	reg group_start; //indicate the initial of a read's data
	
	always@(posedge clk) begin
		if(reset_n) begin
			output_result_ptr <= 0;
			output_mem_ptr <= 0;
			group_start <= 1;
			output_valid <= 0;
			output_data <= 0;
			output_finish <= 0;
			already_output_num <= 0;
		end
		else if(output_permit) begin
			if(output_result_ptr < batch_size) begin 
				if(group_start) begin
					output_valid		 <= 1;
					output_data[9:0]     <= output_result_ptr;
					output_data[63:10]   <= 0;
					output_data[70:64]   <= mem_size_queue[output_result_ptr];
					output_data[127:71]  <= 0;
					output_data[159:128] <= ret_queue[output_result_ptr];
					output_data[511:160] <= 0;
					group_start <= 0;
					curr_size <= mem_size_queue[output_result_ptr];
					already_output_num <= 0;
				end
				else if(already_output_num < curr_size - 1) begin
					output_valid <= 1;
					output_data[255:0] <= mem_queue[output_result_ptr][already_output_num];
					output_data[511:256] <= mem_queue[output_result_ptr][already_output_num+1];
					already_output_num <= already_output_num + 2;	
				end
				else if(already_output_num == curr_size - 1) begin
					output_valid <= 1;
					output_data[255:0] <= mem_queue[output_result_ptr][already_output_num];
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
	end
	
endmodule	