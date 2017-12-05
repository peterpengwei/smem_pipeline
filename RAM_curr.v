module RAM_curr_mem(
	input reset_n,
	input clk,
	
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
	
	//interface with output module
	input output_valid,
	input[9:0] output_read_num,
	output reg [31:0] output_ret,
	output reg [6:0] output_mem_size

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
	always@(posedge clk) begin
		if(mem_size_valid) begin
			mem_size_queue[mem_size_read_num] <= mem_size;
		end
		
		if(ret_valid) begin
			ret_queue[ret_read_num] <= ret;
		end
		
		if(output_valid) begin
			output_mem_size <= mem_size_queue[output_read_num];
			output_ret <= ret_queue[output_read_num];
		end
	end
	
	
	
endmodule	