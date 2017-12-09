`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/26/2017 12:49:32 PM
// Design Name: 
// Module Name: Top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module Top(
	input Clk_32UI,
	input reset_n,
	input stall,
	
	//RAM for reads
	input load_valid,
	input [511:0] load_data,
	input [8:0] batch_size,
	
	//memory requests / responses
	output DRAM_valid,
	output [31:0] addr_k, addr_l,
	
	input DRAM_get,
	input [31:0] cnt_a0,cnt_a1,cnt_a2,cnt_a3,
	input [63:0] cnt_b0,cnt_b1,cnt_b2,cnt_b3,
	input [31:0] cntl_a0,cntl_a1,cntl_a2,cntl_a3,
	input [63:0] cntl_b0,cntl_b1,cntl_b2,cntl_b3,
	
	output output_request,
	input output_permit,
	
	output [511:0] output_data,
	output output_valid,
	output output_finish 
	
);
	
	

	
	//from queue to pipeline
	wire [5:0] status;
	wire [7:0] query; //only send the current query into the pipeline
	wire [6:0] ptr_curr; // record the status of curr and mem queue
	wire [9:0] read_num;
	wire [63:0] ik_x0, ik_x1, ik_x2, ik_info;
	wire [6:0] forward_i;
	wire [6:0] min_intv;
	
	//from pipeline to queue
	wire [5:0] status_out;
	wire [7:0] query_out; //only send the current query into the pipeline
	wire [6:0] ptr_curr_out; // record the status of curr and mem queue
	wire [9:0] read_num_out;
	wire [63:0] ik_x0_out, ik_x1_out, ik_x2_out, ik_info_out;
	wire [6:0] forward_i_out;
	wire [6:0] min_intv_out;
	
	wire [31:0] cnt_a0_out,cnt_a1_out,cnt_a2_out,cnt_a3_out;
	wire [63:0] cnt_b0_out,cnt_b1_out,cnt_b2_out,cnt_b3_out;
	wire [31:0] cntl_a0_out,cntl_a1_out,cntl_a2_out,cntl_a3_out;
	wire [63:0] cntl_b0_out,cntl_b1_out,cntl_b2_out,cntl_b3_out;
	
	
	
	// part 1: load all reads
	wire load_done;
	
	// part 2: provide new read to pipeline	
	wire new_read;
	wire new_read_valid;
	wire [9:0] new_read_num; //should be prepared before hand. every time new_read is set, next_read_num should be updated.
	wire [63:0] new_ik_x0, new_ik_x1, new_ik_x2, new_ik_info;
	wire [6:0] new_forward_i;
	
	
	//part 3: provide new query to queue
	wire [5:0] status_query;
	wire [6:0] query_position;
	wire [8:0] query_read_num;
	wire [7:0] new_read_query;
	
	//part 4: parameters
	wire [63:0] primary, L2_0, L2_1, L2_2, L2_3;
	
	//---------------------
	wire ret_valid;
	wire [31:0] ret;
	wire [9:0] ret_read_num;
	
	wire  [9:0] curr_read_num_1;
	wire  curr_we_1;
	wire  [255:0] curr_data_1;
	wire  [6:0] curr_addr_1;
	
	wire  [9:0] curr_read_num_2;
	wire  curr_we_2;
	wire  [255:0] curr_data_2;
	wire  [6:0] curr_addr_2;
	
	//-------------------------
	
	//interface for backward
	
	// mem queue, port A
	wire [9:0] mem_read_num_1;
	wire mem_we_1;
	wire [255:0] mem_data_1; //[important]sequence: [p_info, p_x2, p_x1, p_x0]
	wire [6:0] mem_addr_1;
	wire [255:0] mem_q_1;
	
	//mem queue, port B
	wire [9:0] mem_read_num_2;
	wire mem_we_2;
	wire [255:0] mem_data_2;
	wire [6:0] mem_addr_2;
	wire [255:0] mem_q_2;
	
	//---------------------------------
	
	//mem size
	wire mem_size_valid;
	wire[6:0] mem_size;
	wire[9:0] mem_size_read_num;
	
	
	
	RAM_read ram_read(
		.reset_n(reset_n),
		.clk(Clk_32UI),
		
		// part 1: load all reads
		.load_valid(load_valid),
		.load_data(load_data),
		.batch_size(batch_size),
		.load_done(load_done),
		
		// part 2: provide new read to pipeline
		.new_read(new_read), //indicate RAM to update new_read
		.new_read_valid(new_read_valid),
		.new_read_num(new_read_num), //equal to read_num
		.new_ik_x0(new_ik_x0), 
		.new_ik_x1(new_ik_x1), 
		.new_ik_x2(new_ik_x2), 
		.new_ik_info(new_ik_info),
		.new_forward_i(new_forward_i),
		
		//part 3: provide new query to queue
		.status_query(status_query),
		.query_position(query_position),
		.query_read_num(query_read_num),
		.new_read_query(new_read_query),
		
		//part 4: parameters
		.primary(primary), 
		.L2_0(L2_0), 
		.L2_1(L2_1),
		.L2_2(L2_2), 
		.L2_3(L2_3)
	);

	Datapath datapath(
		// input of BWT_extend
		.Clk_32UI(Clk_32UI),
		.reset_BWT_extend(reset_n),
		.stall(stall),

		//from memory
		.primary(primary), // fix value
		.L2_0(L2_0),	.L2_1(L2_1),	.L2_2(L2_2),	.L2_3(L2_3), //fix value
		
		.cnt_a0(cnt_a0_out),	.cnt_a1(cnt_a1_out),	.cnt_a2(cnt_a2_out),	.cnt_a3(cnt_a3_out),	
		.cnt_b0(cnt_b0_out),	.cnt_b1(cnt_b1_out),	.cnt_b2(cnt_b2_out),	.cnt_b3(cnt_b3_out),
		.cntl_a0(cntl_a0_out),	.cntl_a1(cntl_a1_out),	.cntl_a2(cntl_a2_out),	.cntl_a3(cntl_a3_out),
		.cntl_b0(cntl_b0_out),	.cntl_b1(cntl_b1_out),	.cntl_b2(cntl_b2_out),	.cntl_b3(cntl_b3_out),
		
		//to memory 
		.DRAM_valid(DRAM_valid),
		.addr_k(addr_k), .addr_l(addr_l),

		//from queue
		.status(status),
		.query(query), //only send the current query into the pipeline
		.ptr_curr(ptr_curr), // record the status of curr and mem queue
		.read_num(read_num),
		.ik_x0(ik_x0), .ik_x1(ik_x1), .ik_x2(ik_x2), .ik_info(ik_info),
		.forward_i(forward_i),
		.min_intv(min_intv),
		
		//to queue
		.status_out(status_out),
		.ptr_curr_out(ptr_curr_out), // record the status of curr and mem queue
		.read_num_out(read_num_out),
		.ik_x0_out(ik_x0_out), .ik_x1_out(ik_x1_out), .ik_x2_out(ik_x2_out), .ik_info_out(ik_info_out),
		.forward_i_out(forward_i_out),
		.min_intv_out(min_intv_out),
		
		//to RAM
		.curr_read_num_1(curr_read_num_1),
		.curr_we_1(curr_we_1),
		.curr_data_1(curr_data_1),
		.curr_addr_1(curr_addr_1),	
		
		.curr_read_num_2(curr_read_num_2),
		.curr_we_2(curr_we_2),
		.curr_data_2(curr_data_2),
		.curr_addr_2(curr_addr_2),
		
		.ret_valid(ret_valid),
		.ret(ret),
		.ret_read_num(ret_read_num)
	);
	
	Queue queue(
		.Clk_32UI(Clk_32UI),
		.reset_n(reset_n),
		.stall(stall),
		
		.DRAM_get(DRAM_get),
		.cnt_a0           (cnt_a0),		.cnt_a1           (cnt_a1),
		.cnt_a2           (cnt_a2),		.cnt_a3           (cnt_a3),
		.cnt_b0           (cnt_b0),		.cnt_b1           (cnt_b1),
		.cnt_b2           (cnt_b2),		.cnt_b3           (cnt_b3),
		.cntl_a0          (cntl_a0),	.cntl_a1          (cntl_a1),
		.cntl_a2          (cntl_a2),	.cntl_a3          (cntl_a3),
		.cntl_b0          (cntl_b0),	.cntl_b1          (cntl_b1),
		.cntl_b2          (cntl_b2),	.cntl_b3          (cntl_b3),
		
		//pipeline to queue
		.status(status_out),
		.ptr_curr(ptr_curr_out), // record the status of curr and mem queue
		.read_num(read_num_out),
		.ik_x0(ik_x0_out), .ik_x1(ik_x1_out), .ik_x2(ik_x2_out), .ik_info(ik_info_out),
		.forward_i(forward_i_out),
		.min_intv(min_intv_out),
		//.next_query_position()
		//queue to pipeline
		.status_out(status),
		.ptr_curr_out(ptr_curr), // record the status of curr and mem queue
		.read_num_out(read_num),
		.ik_x0_out(ik_x0), .ik_x1_out(ik_x1), .ik_x2_out(ik_x2), .ik_info_out(ik_info),
		.forward_i_out(forward_i),
		.min_intv_out(min_intv),
		.query_out(query),
		
		.cnt_a0_out           (cnt_a0_out),		.cnt_a1_out           (cnt_a1_out),
		.cnt_a2_out           (cnt_a2_out),		.cnt_a3_out           (cnt_a3_out),
		.cnt_b0_out           (cnt_b0_out),		.cnt_b1_out           (cnt_b1_out),
		.cnt_b2_out           (cnt_b2_out),		.cnt_b3_out           (cnt_b3_out),
		.cntl_a0_out          (cntl_a0_out),	.cntl_a1_out          (cntl_a1_out),
		.cntl_a2_out          (cntl_a2_out),	.cntl_a3_out          (cntl_a3_out),
		.cntl_b0_out          (cntl_b0_out),	.cntl_b1_out          (cntl_b1_out),
		.cntl_b2_out          (cntl_b2_out),	.cntl_b3_out          (cntl_b3_out),
		
		//interaction with RAM
		
		//fetch new read at the end of queue
		.new_read(new_read),
		.new_read_valid(new_read_valid),
		.load_done(load_done),
		
		.new_read_num(new_read_num), //should be prepared before hand. every time new_read is set, next_read_num should be updated.
		.new_ik_x0(new_ik_x0), .new_ik_x1(new_ik_x1), .new_ik_x2(new_ik_x2), .new_ik_info(new_ik_info),
		.new_forward_i(new_forward_i),
		
		//fetch new query at the start of queue
		.query_position_2RAM(query_position),
		.query_read_num_2RAM(query_read_num),
		.query_status_2RAM(status_query),
		.new_read_query_2Queue(new_read_query)
	);
	
	RAM_curr_mem ram_curr_mem(
		.reset_n(reset_n),
		.clk(clk),
		.stall(stall),
		.batch_size(batch_size),
		
		// curr queue, port A
		.curr_read_num_1(curr_read_num_1),
		.curr_we_1(curr_we_1),
		.curr_data_1(curr_data_1), //[important]sequence: [ik_info, ik_x2, ik_x1, ik_x0]
		.curr_addr_1(curr_addr_1),
		.curr_q_1(curr_q_1),
		
		//curr queue, port B
		.curr_read_num_2(curr_read_num_2),
		.curr_we_2(curr_we_2),
		.curr_data_2(curr_data_2),
		.curr_addr_2(curr_addr_2),
		.curr_q_2(curr_q_2),
		
		//--------------------------------
		
		// mem queue, port A
		.mem_read_num_1(mem_read_num_1),
		.mem_we_1(mem_we_1),
		.mem_data_1(mem_data_1), //[important]sequence: [p_info, p_x2, p_x1, p_x0]
		.mem_addr_1(mem_addr_1),
		.mem_q_1(mem_q_1),
		
		//mem queue, port B
		.mem_read_num_2(mem_read_num_2),
		.mem_we_2(mem_we_2),
		.mem_data_2(mem_data_2),
		.mem_addr_2(mem_addr_2),
		.mem_q_2(mem_q_2),
		
		//---------------------------------
		
		//mem size
		.mem_size_valid(mem_size_valid),
		.mem_size(mem_size),
		.mem_size_read_num(mem_size_read_num),
		
		//ret
		.ret_valid(ret_valid),
		.ret(ret),
		.ret_read_num(ret_read_num),
		
		//---------------------------------
		
		//output module
		.output_request(output_request),
		.output_permit(output_permit),
		.output_data(output_data),
		.output_valid(output_valid),
		.output_finish(output_finish)

	);
	
	
endmodule
