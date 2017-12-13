module CAL_KL(
input wire clk,
input wire rst,
input wire stall,

//data used in this stage
input wire [63:0] p_x0_q,p_x1_q,p_x2_q,p_info_q,

input wire [8:0] read_num_q,
input wire [5:0] status_q,
input wire [63:0] primary_q,
input wire [6:0] current_rd_addr_q,
input wire [6:0] forward_size_n_q,
input wire [6:0] new_size_q,
input wire [6:0] new_last_size_q,
input wire [6:0] current_wr_addr_q,mem_wr_addr_q,
input wire [6:0] backward_i_q, backward_j_q,
input wire [7:0] output_c_q, //[licheng]useless
input wire [6:0] min_intv_q,
input wire finish_sign_q,iteration_boundary_q,
input wire [63:0]	reserved_token_x2_q,
input wire [31:0]	reserved_mem_info_q,

output reg [8:0] read_num,
output reg [6:0] current_rd_addr,

//data handled to next stage (store to read queue)
output reg [6:0] forward_size_n,
output reg [6:0] new_size,
output reg [63:0] primary,
output reg [6:0] new_last_size,
output reg [6:0] current_wr_addr,mem_wr_addr,
output reg [6:0] backward_i, backward_j,
output reg [6:0] output_c, //[licheng]
output reg [6:0] min_intv,
output reg finish_sign,
output reg [6:0] mem_size,
output reg iteration_boundary,
output reg [63:0] backward_k,backward_l,
output reg request_valid,
output reg [41:0] addr_k,addr_l,
output reg [63:0] p_x0,p_x1,p_x2,p_info,
output reg [63:0]	reserved_token_x2,
output reg [31:0]	reserved_mem_info,
output reg [5:0] status

);
	localparam [5:0]
	F_init	= 6'h0,	//000
	F_run	= 6'h1,	//001
	F_break = 6'h2,	//010
	BCK_INI = 6'h4,	//100
	BCK_RUN = 6'h5,	//101
	BCK_END = 6'h6,	//110
	BUBBLE  = 6'h30,
	DONE	= 6'b100000;


	//signals handled to READ parse unit
	wire [5:0] status_d;
	wire [63:0] backward_k_d,backward_l_d; //could be 40 bits
	wire [63:0] backward_k_temp,backward_l_temp;
	wire [6:0] mem_size_d;
	assign	backward_k_temp = p_x0_q - 1;
	assign	backward_l_temp = backward_k_temp + p_x2_q;
	assign 	backward_k_d	= (backward_k_temp >= primary_q) ? backward_k_temp - 1 : backward_k_temp;
	assign	backward_l_d	= (backward_l_temp >= primary_q) ? backward_l_temp - 1 : backward_l_temp;
	assign status_d = finish_sign_q? BCK_END : status_q;
	assign mem_size_d = mem_wr_addr_q; 
	always @(posedge clk) begin
		if(!rst)begin
			backward_k	<= 0;
			backward_l	<= 0;
			addr_k		<= 0;
			addr_l		<= 0;

			p_x0				<= 0;
			p_x1				<= 0;
			p_x2				<= 0;
			p_info				<= 0;
			finish_sign			<= 0;
			iteration_boundary	<= 0;
			backward_i			<= 0;
			backward_j			<= 0;
			output_c			<= 0;
			current_wr_addr		<= 0;
			current_rd_addr		<= 0;
			mem_size			<= 0;
			min_intv			<= 0;
			new_size			<= 0;
			read_num			<= 0;

			mem_wr_addr			<= 0;
			forward_size_n		<= 0;
			new_last_size		<= 0;
			primary				<= 0;
			reserved_token_x2	<= 0;
			reserved_mem_info	<= 0;
			request_valid		<= 0;
			status				<= BUBBLE;
		end	
		else if (stall == 1) begin
			primary		<= primary;
			reserved_token_x2	<= reserved_token_x2;
			reserved_mem_info	<= reserved_mem_info;
			backward_k  <= backward_k;
			backward_l  <= backward_l;

			//the real valid signal connected to interface should be 
			//(request_valid & stall == 0)
			request_valid <= 0; 
			addr_k		<= addr_k;
			addr_l		<= addr_l;

			p_x0				<= p_x0;
			p_x1				<= p_x1;
			p_x2				<= p_x2;
			p_info				<= p_info;
			finish_sign			<= 0;
			iteration_boundary	<= iteration_boundary;
			backward_i			<= backward_i;
			backward_j			<= backward_j;
			output_c			<= backward_i; //[licheng]
			current_wr_addr		<= current_wr_addr;
			current_rd_addr		<= current_rd_addr;
		
			min_intv			<= min_intv;
			new_size			<= new_size;
			mem_size			<= mem_size;
			read_num			<= read_num;
			mem_wr_addr			<= mem_wr_addr;
			forward_size_n		<= forward_size_n;
			new_last_size		<= new_last_size;
			status				<= status;
		end
		else if(status_d==BCK_INI) begin
		//received curr value from queue
			p_x0				<= p_x0_q;
			p_x1				<= p_x1_q;
			p_x2				<= p_x2_q;
			p_info				<= p_info_q;
		//generated
			backward_k			<= backward_k_d;
			backward_l			<= backward_l_d;
			request_valid		<= 1'b1;
			addr_k				<= {backward_k_d[34:7], 4'b0};
			addr_l				<= {backward_l_d[34:7], 4'b0};

		// always request current bp, output to read array.
			read_num			<= read_num_q;
			backward_i			<= backward_i_q;
		// 
			backward_j			<= backward_j_q;
		
			primary				<= primary_q;
			finish_sign			<= 0;
			reserved_token_x2	<= reserved_token_x2_q;
			reserved_mem_info	<= reserved_mem_info_q;
			iteration_boundary	<= iteration_boundary_q;

			output_c			<= backward_i_q; //[licheng]
			current_wr_addr		<= current_wr_addr_q;
			current_rd_addr		<= current_rd_addr_q;
		
			min_intv			<= min_intv_q;
			new_size			<= new_size_q;
			mem_size			<= 0;
			mem_wr_addr			<= mem_wr_addr_q;
			forward_size_n		<= forward_size_n_q;
			new_last_size		<= new_last_size_q;
			status				<= BCK_RUN;
		
		end
		else if(status_d==BCK_RUN) begin
			primary		<= primary_q;
			reserved_token_x2	<= reserved_token_x2_q;
			reserved_mem_info	<= reserved_mem_info_q;
			backward_k  <= backward_k_d;
			backward_l  <= backward_l_d;

			request_valid <= 1'b1;
			addr_k		<= {backward_k_d[34:7], 4'b0};
			addr_l		<= {backward_l_d[34:7], 4'b0};

			p_x0				<= p_x0_q;
			p_x1				<= p_x1_q;
			p_x2				<= p_x2_q;
			p_info				<= p_info_q;
			finish_sign			<= 0;
			iteration_boundary	<= iteration_boundary_q;
			backward_i			<= backward_i_q;
			backward_j			<= backward_j_q;
			output_c			<= backward_i_q; //[licheng]
			current_wr_addr		<= current_wr_addr_q;
			current_rd_addr		<= current_rd_addr_q;
		
			min_intv			<= min_intv_q;
			new_size			<= new_size_q;
			mem_size			<= mem_wr_addr_q;
			read_num			<= read_num_q;
			mem_wr_addr			<= mem_wr_addr_q;
			forward_size_n		<= forward_size_n_q;
			new_last_size		<= new_last_size_q;
			status				<= status_d;
				
		end
		else if(status_d==BCK_END) begin
			//outputing to finish
			finish_sign			<= 1;
			mem_size			<= mem_wr_addr_q;
			read_num			<= read_num_q;
			
			backward_k	<= 0;
			backward_l	<= 0;
			addr_k		<= 0;
			addr_l		<= 0;

			p_x0				<= 0;
			p_x1				<= 0;
			p_x2				<= 0;
			p_info				<= 0;

			iteration_boundary	<= 0;
			backward_i			<= 0;
			backward_j			<= 0;
			output_c			<= 0;
			current_wr_addr		<= 0;
			current_rd_addr		<= 0;
		
			min_intv			<= 0;
			new_size			<= 0;
			
			mem_wr_addr			<= 0;
			forward_size_n		<= 0;
			new_last_size		<= 0;
			primary				<= 0;
			reserved_token_x2	<= 0;
			reserved_mem_info	<= 0;
			request_valid		<= 0;
			status				<= BUBBLE; //directly outputing BUBBLE to queue
		end
		else begin //BUBBLE
			backward_k	<= 0;
			backward_l	<= 0;
			addr_k		<= 0;
			addr_l		<= 0;

			p_x0				<= 0;
			p_x1				<= 0;
			p_x2				<= 0;
			p_info				<= 0;
			finish_sign			<= 0;
			mem_size			<= 0;
			iteration_boundary	<= 0;
			backward_i			<= 0;
			backward_j			<= 0;
			output_c			<= 0;
			current_wr_addr		<= 0;
			current_rd_addr		<= 0;
		
			min_intv			<= 0;
			new_size			<= 0;
			read_num			<= 0;
			mem_wr_addr			<= 0;
			forward_size_n		<= 0;
			new_last_size		<= 0;
			primary				<= 0;
			reserved_token_x2	<= 0;
			reserved_mem_info	<= 0;
			request_valid		<= 0;
			status				<= BUBBLE;
		end
	end

endmodule 