

module control_top_back(
input  clk,
input  rst,
input  stall,

///////////////////////signals needs to be registered//////start////////
input  [`READ_NUM_WIDTH - 1:0] read_num_q,
input  [5:0] status_q,
input  [6:0] forward_size_n_q,
input  [6:0] new_size_q,
input  [63:0] primary_q,
input  [6:0] new_last_size_q,
input  [6:0] current_wr_addr_q,current_rd_addr_q,mem_wr_addr_q,
input  [6:0] backward_i_q,backward_j_q,
input  [7:0] output_c_q,
input  [6:0] min_intv_q,
input  iteration_boundary_q,
input  [63:0] p_x0_q,p_x1_q,p_x2_q,p_info_q,
input  [31:0] last_mem_info,
input  [63:0] last_token_x2,
//data portion
input  [6:0] backward_x, //backward_x only used once in the init stage
/////////////////////signals needs to be registered///////end///////

input  [63:0] ok0_x0, ok0_x1, ok0_x2,
input  [63:0] ok1_x0, ok1_x1, ok1_x2,
input  [63:0] ok2_x0, ok2_x1, ok2_x2,
input  [63:0] ok3_x0, ok3_x1, ok3_x2,

input [63:0] ok_b_temp_x0,ok_b_temp_x1,ok_b_temp_x2,


//stage 3 input
input  [63:0] p_x0_q_S3,p_x1_q_S3,p_x2_q_S3,p_info_q_S3,

//stage 1 output
output  [`READ_NUM_WIDTH - 1:0]	read_num_S1,
output 			store_valid_mem,			
output  [63:0]	mem_x_0,
output  [63:0]	mem_x_1,
output  [63:0]	mem_x_2,
output  [63:0]	mem_x_info,
output  [6:0]    mem_x_addr,

output 			store_valid_curr,			
output  [63:0]	curr_x_0,
output  [63:0]	curr_x_1,
output  [63:0]	curr_x_2,
output  [63:0]	curr_x_info,
output  [6:0]    curr_x_addr,

//stage 2 output 
output  [`READ_NUM_WIDTH - 1:0] read_num_S2,
output  [6:0] current_rd_addr_S2,

//stage 3 ////final stage output
output [5:0] status_query_B,
output [`READ_NUM_WIDTH - 1:0] read_num_query_B,
output [6:0] next_query_position_B,

output  [`READ_NUM_WIDTH - 1:0] read_num,
output  [6:0] forward_size_n,
output  [6:0] new_size,
output  [63:0] primary,
output  [6:0] new_last_size,
output  [6:0] current_rd_addr, current_wr_addr,mem_wr_addr,
output  [6:0] backward_i, backward_j,
output  [7:0] output_c,
output  [6:0] min_intv,

output  iteration_boundary,
output  [63:0] backward_k,backward_l, //output to bwt_extend but not used in control logic

output  [63:0] p_x0,p_x1,p_x2,p_info,
output  [63:0]	reserved_token_x2,
output  [31:0]	reserved_mem_info,

///backward_i and read_num for requesting new bp

///memory requesting
output  request_valid,
output  [41:0] addr_k,addr_l,
//finish sign
output  finish_sign,
output  [6:0] mem_size,
output  [5:0] status
);
	`include "pipeline_head.vh"
	
	wire [6:0] backward_x_B1;
	wire [`READ_NUM_WIDTH - 1:0] read_num_B1;
	wire [63:0] ok0_x0_B1, ok0_x1_B1, ok0_x2_B1;
	wire [63:0] ok1_x0_B1, ok1_x1_B1, ok1_x2_B1;
	wire [63:0] ok2_x0_B1, ok2_x1_B1, ok2_x2_B1;
	wire [63:0] ok3_x0_B1, ok3_x1_B1, ok3_x2_B1;
	wire [63:0] p_x0_B1,p_x1_B1,p_x2_B1,p_info_B1;
	wire [6:0] min_intv_B1;
	wire iteration_boundary_B1,iteration_boundary_B2;
	wire [6:0] backward_i_B1,backward_j_B1;
	wire [6:0] current_wr_addr_B1,current_rd_addr_B1,mem_wr_addr_B1;
	wire [6:0] new_size_B1;
	wire [6:0] new_last_size_B1;
	wire [6:0] forward_size_n_B1;

	wire [31:0] last_mem_info_B1;
	wire [63:0] last_token_x2_B1;
	
	
	//signals handled to next stage
	wire [`READ_NUM_WIDTH - 1:0]	read_num_B2,read_num_B3;
	wire [6:0]	new_size_B2;
	wire [6:0]	current_wr_addr_B2,current_rd_addr_B2,mem_wr_addr_B2;
	wire [63:0]	reserved_token_x2_B2;
	wire [31:0]	reserved_mem_info_B2;
	wire [6:0]	min_intv_B2;
	wire [6:0]	backward_i_B2,backward_j_B2;
	wire [6:0]	new_last_size_B2,forward_size_n_B2;

	//signals handled to storage unit
	wire	store_valid_mem_B2, store_valid_curr_B2;
	wire [7:0] output_c_B1,output_c_B2,output_c_B3,output_c_B4;
	wire [63:0] primary_B1, primary_B2, primary_B3, primary_B4;


	wire finish_sign_B3,iteration_boundary_B3;
	wire [6:0]	current_wr_addr_B3,current_rd_addr_B3,mem_wr_addr_B3;
	wire [6:0]	new_size_B3;
	wire [63:0]	reserved_token_x2_B3;
	wire [63:0]	reserved_token_x2_B4;
	wire [31:0]	reserved_mem_info_B3,reserved_mem_info_B4;
	wire [6:0]	min_intv_B3;
	wire [6:0]	backward_i_B3,backward_j_B3;
	wire [6:0]	new_last_size_B3,forward_size_n_B3;
	wire [63:0] p_x0_B3,p_x1_B3,p_x2_B3,p_info_B3;
	wire [5:0] status_B2,status_B3;
	wire [`READ_NUM_WIDTH - 1:0]	read_num_B4;
	wire [6:0]	current_wr_addr_B4,current_rd_addr_B4,mem_wr_addr_B4;
	wire [6:0]	min_intv_B4;
	wire [6:0]	backward_i_B4,backward_j_B4;
	wire [6:0]	new_last_size_B4,forward_size_n_B4;
	wire [6:0]	new_size_B4;
	wire finish_sign_B4,iteration_boundary_B4;
	wire [63:0] p_x0_B4,p_x1_B4,p_x2_B4,p_info_B4;
	wire [63:0] backward_k_B4,backward_l_B4;
	wire [41:0] addr_k_B4,addr_l_B4;

	assign read_num_S1 = read_num_B2;
	assign read_num_S2 = read_num_B2;
	assign current_rd_addr_S2 = current_rd_addr_B2;

//data portion
 CONTROL_STAGE1 bc1(
	.clk(clk),
	.rst(rst),
	.stall(stall),
	.read_num_q(read_num_q),
	.status_q(status_q),
	.backward_x(backward_x),
	.primary_q(primary_q),
//data portion
     .ok0_x0           (ok0_x0),
     .ok0_x1           (ok0_x1),
     .ok0_x2           (ok0_x2),     
     .ok1_x0           (ok1_x0),     
     .ok1_x1           (ok1_x1),     
     .ok1_x2           (ok1_x2),     
     .ok2_x0           (ok2_x0),     
     .ok2_x1           (ok2_x1),     
     .ok2_x2           (ok2_x2),     
     .ok3_x0           (ok3_x0),     
     .ok3_x1           (ok3_x1),     
     .ok3_x2           (ok3_x2), 
	 
	.ok_b_temp_x0(ok_b_temp_x0),
	.ok_b_temp_x1(ok_b_temp_x1),
	.ok_b_temp_x2(ok_b_temp_x2),
	
	 .p_x0(p_x0_q),.p_x1(p_x1_q),
	 .p_x2(p_x2_q),.p_info(p_info_q),

	.min_intv_q(min_intv_q),
	.iteration_boundary_q(iteration_boundary_q),
	.backward_i_q(backward_i_q),.backward_j_q(backward_j_q),
	.current_wr_addr_q(current_wr_addr_q),
	.current_rd_addr_q(current_rd_addr_q),
	.mem_wr_addr_q(mem_wr_addr_q),

	.new_size_q(new_size_q),
	.new_last_size_q(new_last_size_q),
	.forward_size_n_q(forward_size_n_q),

	.last_mem_info(last_mem_info),
	.last_token_x2(last_token_x2),
	.output_c_q(output_c_q),
	

//signals handled to next stage
	.read_num(read_num_B2),
	.new_size(new_size_B2),
	.primary(primary_B2),
	.current_wr_addr(current_wr_addr_B2),
	.current_rd_addr(current_rd_addr_B2),
	.mem_wr_addr(mem_wr_addr_B2),
	.reserved_token_x2(reserved_token_x2_B2),
	.reserved_mem_info(reserved_mem_info_B2),
	.min_intv(min_intv_B2),
	.backward_i(backward_i_B2),.backward_j(backward_j_B2),
	.new_last_size(new_last_size_B2),.forward_size_n(forward_size_n_B2),
	.output_c(output_c_B2),

	//signals handled to storage unit
	.store_valid_mem(store_valid_mem),
	.mem_x_0(mem_x_0),
	.mem_x_1(mem_x_1),
	.mem_x_2(mem_x_2),
	.mem_x_info(mem_x_info),
	.mem_x_addr(mem_x_addr),

	.store_valid_curr(store_valid_curr),
	.curr_x_0(curr_x_0),
	.curr_x_1(curr_x_1),
	.curr_x_2(curr_x_2),
	.curr_x_info(curr_x_info),
	.curr_x_addr(curr_x_addr),

	.iteration_boundary(iteration_boundary_B2),
	.status(status_B2)
);  

CONTROL_STAGE2 bc2(
	.clk(clk),
	.rst(rst),
	.stall(stall),

	.read_num_q(read_num_B2),
	.status_q(status_B2),
	.primary_q(primary_B2),
	.forward_size_n_q(forward_size_n_B2),
	.new_size_q(new_size_B2),
	.new_last_size_q(new_last_size_B2),

	.current_wr_addr_q(current_wr_addr_B2),
	.current_rd_addr_q(current_rd_addr_B2),
	.mem_wr_addr_q(mem_wr_addr_B2),
	.backward_i_q(backward_i_B2),
	.backward_j_q(backward_j_B2),

	.output_c_q(output_c_B2),
	.min_intv_q(min_intv_B2),
	.reserved_token_x2_q(reserved_token_x2_B2),
	.reserved_mem_info_q(reserved_mem_info_B2),
	.iteration_boundary_q(iteration_boundary_B2),

//requesting new curr entry
	.read_num(read_num_B3),
	.current_rd_addr(current_rd_addr_B3),

	.primary(primary_B3),
	.forward_size_n(forward_size_n_B3),
	.new_size(new_size_B3),
	.new_last_size(new_last_size_B3),
	.current_wr_addr(current_wr_addr_B3),
	.mem_wr_addr(mem_wr_addr_B3),
	.backward_i(backward_i_B3),.backward_j(backward_j_B3),
	.output_c(output_c_B3),
	.min_intv(min_intv_B3),
	.finish_sign(finish_sign_B3),.iteration_boundary(iteration_boundary_B3),
	.reserved_token_x2(reserved_token_x2_B3),
	.reserved_mem_info(reserved_mem_info_B3),
	.status(status_B3)
);   



CAL_KL bc3(
	.clk(clk),
	.rst(rst),
	.stall(stall),
//data used in this stage

	.p_x0_licheng(p_x0_q_S3),.p_x1_licheng(p_x1_q_S3),
	.p_x2_licheng(p_x2_q_S3),.p_info_licheng(p_info_q_S3),

	.read_num_licheng(read_num_B3),

	.status_licheng(status_B3),
	.primary_licheng(primary_B3),
	.current_rd_addr_licheng(current_rd_addr_B3),
	.forward_size_n_licheng(forward_size_n_B3),
	.new_size_licheng(new_size_B3),
	.new_last_size_licheng(new_last_size_B3),
	.current_wr_addr_licheng(current_wr_addr_B3),
	.mem_wr_addr_licheng(mem_wr_addr_B3),
	.backward_i_licheng(backward_i_B3),.backward_j_licheng(backward_j_B3),
	.output_c_licheng(output_c_B3),
	.min_intv_licheng(min_intv_B3),
	.finish_sign_licheng(finish_sign_B3),.iteration_boundary_licheng(iteration_boundary_B3),
	.reserved_token_x2_licheng(reserved_token_x2_B3),
	.reserved_mem_info_licheng(reserved_mem_info_B3),
	
	.read_num(read_num),
	.current_rd_addr(current_rd_addr),
	.forward_size_n(forward_size_n),
	.new_size(new_size),
	.primary(primary),
	.new_last_size(new_last_size),
	.current_wr_addr(current_wr_addr),
	.mem_wr_addr(mem_wr_addr),
	.backward_i(backward_i), 
	.backward_j(backward_j),
	.output_c(output_c),
	.min_intv(min_intv),
	
	//[licheng] query request one cycle ahead
	.next_query_position_B(next_query_position_B),
	.read_num_query_B(read_num_query_B),
	.status_query_B(status_query_B),
 
	//outputing finish_sign+read_num+mem_size to another module
	.finish_sign(finish_sign),
	.mem_size(mem_size),
	
	.iteration_boundary(iteration_boundary),
	.backward_k(backward_k),
	.backward_l(backward_l),
	.request_valid(request_valid),
	.addr_k(addr_k),.addr_l(addr_l),
	.p_x0(p_x0),.p_x1(p_x1),
	.p_x2(p_x2),.p_info(p_info),
	.reserved_token_x2(reserved_token_x2),
	.reserved_mem_info(reserved_mem_info),
	.status(status)
); 

endmodule