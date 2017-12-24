`define CL 512
`define MAX_READ 64
`define READ_NUM_WIDTH 6

module afu_core(
	input  wire                             CLK_400M,
	input  wire                             CLK_200M,
    input  wire                             reset_n,
    
	//---------------------------------------------------
    //input  wire                             spl_enable,
	input  wire 							core_start_d,
	//---------------------------------------------------
	
    input  wire                             spl_reset,
    
    // TX_RD request, afu_core --> afu_io
    input  wire                             spl_tx_rd_almostfull,
    output reg                              cor_tx_rd_valid,
    output reg  [57:0]                      cor_tx_rd_addr,
    output reg  [5:0]                       cor_tx_rd_len,  //[licheng]useless.
    
    
    // TX_WR request, afu_core --> afu_io
    input  wire                             spl_tx_wr_almostfull,    
    output reg                              cor_tx_wr_valid,
    output reg                              cor_tx_dsr_valid,
    output reg                              cor_tx_fence_valid,
    output                               cor_tx_done_valid,
    output reg  [57:0]                      cor_tx_wr_addr, 
    output reg  [5:0]                       cor_tx_wr_len, 
    output reg  [511:0]                     cor_tx_data,
             
    // RX_RD response, afu_io --> afu_core
    input  wire                             io_rx_rd_valid,
    input  wire [511:0]                     io_rx_data,    
                 
    // afu_csr --> afu_core, afu_id
    input  wire                             csr_id_valid,
    output reg                              csr_id_done,    
    input  wire [31:0]                      csr_id_addr,
        
     // afu_csr --> afu_core, afu_ctx   
    input  wire                             csr_ctx_base_valid,
    input  wire [57:0]                      csr_ctx_base,

	input  [63:0]	dsm_base_addr,	
	input  [63:0] 						io_src_ptr,
	input  [63:0] 						io_dst_ptr,
	
	//for test
	output [6:0] backward_i_q_test,
	output [6:0] backward_j_q_test
);
	assign cor_tx_done_valid = 1'b0;
	
	reg core_start;
	always@(posedge CLK_200M) core_start <= core_start_d;
	
	reg batch_reset_n;
	// 400M domain
	reg spl_tx_rd_almostfull_q, spl_tx_wr_almostfull_q;
	always@(CLK_400M) begin
		spl_tx_rd_almostfull_q <= spl_tx_rd_almostfull;
		spl_tx_wr_almostfull_q <= spl_tx_wr_almostfull;
	end
	
	//send out addr_k & addr_l
	
	wire FIFO_request_Data_valid;
	wire [57:0] FIFO_request_Data_out;
	
	always@(posedge CLK_400M) begin
		if(!reset_n) begin
			cor_tx_rd_valid <= 0;
			cor_tx_rd_addr <= 0;
		end
		else begin			
			cor_tx_rd_valid <= FIFO_request_Data_valid;
			cor_tx_rd_addr <= FIFO_request_Data_out;
		end
	end
	
	//receive k_response & l_response
	
	reg odd_even_tag_in;
	reg [511:0] FIFO_response_k_Data_in;
	reg FIFO_response_k_WriteEn_in;
	reg [511:0] FIFO_response_l_Data_in;
	reg FIFO_response_l_WriteEn_in;
	
	always@(posedge CLK_400M) begin
		if(!reset_n) begin
			odd_even_tag_in <= 0;
			
			FIFO_response_k_Data_in <= 0;
			FIFO_response_k_WriteEn_in <= 0;
			FIFO_response_l_Data_in <= 0;
			FIFO_response_l_WriteEn_in <= 0;
		end
		else begin
			if(odd_even_tag_in) begin
				FIFO_response_k_WriteEn_in <= 0;
				FIFO_response_l_WriteEn_in <= io_rx_rd_valid;
				FIFO_response_l_Data_in <= io_rx_data;
			end
			else begin
				FIFO_response_k_WriteEn_in <= io_rx_rd_valid;
				FIFO_response_l_WriteEn_in <= 0;
				FIFO_response_k_Data_in <= io_rx_data;
			end
			
			if (io_rx_rd_valid) begin
				odd_even_tag_in <= ~odd_even_tag_in;
			end
		end
	end
	
	//send out result
	
	wire FIFO_output_Data_valid;
	wire [512+57:0] FIFO_output_Data_out;
	
	always@(posedge CLK_400M) begin
		if(!reset_n) begin
			cor_tx_wr_valid <= 0;
			cor_tx_fence_valid <= 0;
			cor_tx_wr_addr <= 0; 
			cor_tx_data <= 0;
		end
		else begin
			cor_tx_wr_valid <= FIFO_output_Data_valid;
			cor_tx_fence_valid <= FIFO_output_Data_out[511]; //[licheng] use the 511 bit to represent fence valid.
			cor_tx_wr_addr <= FIFO_output_Data_out[512+57:512];
			cor_tx_data	<= FIFO_output_Data_out[511:0];
		end
	end
	
	//====================================================================
	
	//output FIFO
	reg [512+57:0] FIFO_output_Data_in;
	reg FIFO_output_WriteEn_in;
	
	aFIFO #(.DATA_WIDTH(512+58), .ADDRESS_WIDTH(4)) FIFO_output(
		.Clear_in(!core_start),
		.CLK_400M(CLK_400M),
		
		//200M
		.Data_in(FIFO_output_Data_in),
		.WriteEn_in(FIFO_output_WriteEn_in),
		.Full_out(),
		.WClk(CLK_200M),
		
		//400M
		.Data_out(FIFO_output_Data_out),
		.Data_valid(FIFO_output_Data_valid),
		.ReadEn_in(1),
		.Empty_out(FIFO_output_Empty_out),
		.RClk(CLK_400M)
	);
	
	//response FIFO k
	
	wire FIFO_response_k_Empty_out, FIFO_response_l_Empty_out;
	wire both_not_empty = (!FIFO_response_k_Empty_out) & (!FIFO_response_l_Empty_out);
	
	wire FIFO_response_k_Data_valid, FIFO_response_l_Data_valid;
	wire both_valid = FIFO_response_k_Data_valid & FIFO_response_l_Data_valid;
	
	wire [511:0] FIFO_response_k_Data_out, FIFO_response_l_Data_out;
	
	
	
	aFIFO #(.DATA_WIDTH(512), .ADDRESS_WIDTH(4)) FIFO_response_k(
		.Clear_in(!core_start),
		
		//400M
		.Data_in(FIFO_response_k_Data_in),
		.WriteEn_in(FIFO_response_k_WriteEn_in),
		.Full_out(),
		.WClk(CLK_400M),
		
		//200M
		.Data_out(FIFO_response_k_Data_out),
		.Data_valid(FIFO_response_k_Data_valid),
		
		//read out the results a pair at a time
		.ReadEn_in(both_not_empty), 
		.Empty_out(FIFO_response_k_Empty_out),
		.RClk(CLK_200M)
	);
	
	//response FIFO l
	aFIFO #(.DATA_WIDTH(512), .ADDRESS_WIDTH(4)) FIFO_response_l(
		.Clear_in(!core_start),
		
		//400M
		.Data_in(FIFO_response_l_Data_in),
		.WriteEn_in(FIFO_response_l_WriteEn_in),
		.Full_out(),
		.WClk(CLK_400M),
		
		//200M
		.Data_out(FIFO_response_l_Data_out),
		.Data_valid(FIFO_response_l_Data_valid),
		.ReadEn_in(both_not_empty), 
		.Empty_out(FIFO_response_l_Empty_out),
		.RClk(CLK_200M)
	);
	
	reg [57:0] FIFO_request_Data_in_1, FIFO_request_Data_in_2;
	reg FIFO_request_WriteEn_in_2;
	wire [`READ_NUM_WIDTH-1:0] DRAM_read_num;
	wire [`READ_NUM_WIDTH-1:0] DRAM_read_num_out;
	wire [`READ_NUM_WIDTH-1:0] DRAM_read_num_out;
	
	// request FIFO addr k
	aFIFO_2w_1r #(.DATA_WIDTH(58+`READ_NUM_WIDTH), .ADDRESS_WIDTH(4)) FIFO_request(
		.Clear_in(!core_start),
		
		//200M
		.Data_in_1({DRAM_read_num, FIFO_request_Data_in_1}),
		.Data_in_2({DRAM_read_num, FIFO_request_Data_in_2}),
		.WriteEn_in_2(FIFO_request_WriteEn_in_2),
		.Full_out(),
		.WClk(CLK_200M),
		
		//400M
		.Data_out({DRAM_read_num_out, FIFO_request_Data_out}),
		.Data_valid(FIFO_request_Data_valid),
		.ReadEn_in(1),
		.Empty_out(),
		.RClk(CLK_400M)
	);
	
	
	//==========================================================================
	
	// 200M domain
	
	
	wire stall = spl_tx_rd_almostfull | spl_tx_wr_almostfull | spl_tx_rd_almostfull_q | spl_tx_wr_almostfull_q;
	
	wire [57:0] hand_ptr = io_src_ptr + 50331648 + 16384 - 1;
	wire [57:0] input_base = io_src_ptr + 50331648 + 16384;
	wire [57:0] output_base = io_dst_ptr;
	wire [57:0] BWT_base = io_src_ptr;
	
	reg polling_tag;
	wire BWT_read_tag_0 = FIFO_response_l_Data_out[480];
	wire BWT_read_tag_1 = FIFO_response_l_Data_out[482];
	
	//note batch size must be 1 bit wider than memory. e.g. 256 reads takes 8 bits to present.
	wire 	[`READ_NUM_WIDTH+1 - 1:0] batch_size_temp = FIFO_response_l_Data_out[`READ_NUM_WIDTH+1 - 1 + 448:448];	
	reg 	[`READ_NUM_WIDTH+1 - 1:0] batch_size;
	
	//[licheng] very dangerous here.
	wire 	[`READ_NUM_WIDTH+1+2 - 1:0] CL_num = batch_size << 2;
	reg 	[`READ_NUM_WIDTH+1+2 - 1:0] load_ptr;
	
	reg  [57:0] output_addr;
	wire [57:0] licheng_tx_wr_addr = output_addr + output_base;
	
	parameter IDLE 		= 8'b0000_0001;
	parameter POLLING_1 = 8'b0000_0010;
	parameter POLLING_2 = 8'b0000_0100;
	parameter LOAD_READ = 8'b0000_1000;
	parameter RUN 		= 8'b0001_0000;
	parameter OUTPUT 	= 8'b0010_0000;
	parameter FINAL 	= 8'b0100_0000;
	parameter FINAL_2 	= 8'b1000_0000;
	reg [7:0] state;
	
	
	wire read_load_done;
	reg load_valid;
	reg [511:0] load_data;
	
	wire output_request_200M;
	wire DRAM_valid;
	wire [31:0] addr_k, addr_l;
	
	reg DRAM_get;
	reg [511:0] CL_1_200M, CL_2_200M;
	
	reg output_permit;
	wire output_finish_200M;
	wire output_valid_200M;
	wire [511:0] output_data_200M;
	
	always@(posedge CLK_200M) begin
		if(!reset_n) begin
			state <= IDLE;
			
			batch_reset_n <= 0;
			polling_tag <= 0;
			load_ptr <= 0;
			output_addr<= 0;
			load_valid <= 0;
			load_data <= 0;
			DRAM_get <= 0;
			CL_1_200M <= 0;
			CL_2_200M <= 0;
			output_permit <= 0;
		end
		else begin
			case(state)
				IDLE: begin
					batch_reset_n <= 0;
					
					//never reset polling_tag!
					load_ptr <= 0;
					output_addr<= 0;
					load_valid <= 0;
					load_data <= 0;
					DRAM_get <= 0;
					CL_1_200M <= 0;
					CL_2_200M <= 0;
					output_permit <= 0;
					
					FIFO_output_WriteEn_in <= 0;
					FIFO_request_WriteEn_in_2 <= 0;
					FIFO_output_Data_in <= 0;
					if(core_start)state <= POLLING_1;
				end
				
				POLLING_1: begin
					batch_reset_n <= 1;
					if(!stall) begin
						FIFO_request_Data_in_1 <= hand_ptr;
						FIFO_request_Data_in_2 <= hand_ptr;
						FIFO_request_WriteEn_in_2 <= 1;
					
						state <= POLLING_2;
					end
					else begin
						FIFO_request_WriteEn_in_2 <= 0;
						state <= POLLING_1;
					end
				end
				
				POLLING_2: begin
					FIFO_request_WriteEn_in_2 <= 0;
					
					if(both_valid) begin
						if(BWT_read_tag_0 && (polling_tag==0)) begin
							state <= LOAD_READ;
							batch_size <= batch_size_temp;
							
							polling_tag <= ~polling_tag;
						end
						else if(BWT_read_tag_1 && (polling_tag==1)) begin
							state <= LOAD_READ;
							batch_size <= batch_size_temp;
							
							polling_tag <= ~polling_tag;
						end
						else begin
							state <= POLLING_1;
						end
					end
				end
				
				LOAD_READ : begin
					//memory request
					if(load_ptr < CL_num) begin
						if(!stall) begin
							//send out two identical request for compatibility with other modules
							FIFO_request_Data_in_1 <= input_base + load_ptr;
							FIFO_request_Data_in_2 <= input_base + load_ptr;
							FIFO_request_WriteEn_in_2 <= 1;
						
							load_ptr <= load_ptr + 1;
						end 
						else begin
							FIFO_request_WriteEn_in_2 <= 0;
						end
					end
					else begin
						FIFO_request_WriteEn_in_2 <= 0;
					end
					
					//memory responses
					if(both_valid) begin
						load_valid <= 1;
						load_data <= FIFO_response_k_Data_out; //two responses should be the same
					end
					else begin
						load_valid <= 0;
					end
					
					//control
					if(read_load_done) begin
						state <= RUN;
					end
				
				end
				
				RUN: begin
					if(!output_request_200M) begin
						//send out request
						// if(!stall) begin
							FIFO_request_Data_in_1 <= BWT_base + addr_k[31:4];
							FIFO_request_Data_in_2 <= BWT_base + addr_l[31:4];
							FIFO_request_WriteEn_in_2 <= DRAM_valid;
						// end
						// else begin
							// FIFO_request_WriteEn_in_2 <= 0;
						// end
						
						//get response
						DRAM_get <= both_valid;
						CL_1_200M <= FIFO_response_k_Data_out;
						CL_2_200M <= FIFO_response_l_Data_out;
					end
					
					else begin
						FIFO_request_WriteEn_in_2 <= 0;
						output_permit <= 1;
						state <= OUTPUT;
					end
				end
				
				OUTPUT: begin
					// if(!stall) begin
						if(!output_finish_200M) begin
							FIFO_output_WriteEn_in <= output_valid_200M;
							FIFO_output_Data_in[512+57:512] <= output_addr + output_base;
							FIFO_output_Data_in[511:0]      <= output_data_200M;
						
							if(output_valid_200M) output_addr <= output_addr + 1;
						end
						else begin
							FIFO_output_WriteEn_in 			<= 1;
							FIFO_output_Data_in[512+57:512] <= 0;
							FIFO_output_Data_in[511:0]      <= {1'b1,511'b0}; //fence
							state <= FINAL;					
						end
					// end
					// else begin
						// FIFO_output_WriteEn_in <= 0;
					// end					
				end
				
				FINAL : begin
					if(!stall) begin
						FIFO_output_WriteEn_in <= 1;
						FIFO_output_Data_in[512+57:512] <= hand_ptr;
						FIFO_output_Data_in[511:480]    <= 16;
						FIFO_output_Data_in[479:0]    <= 0;
						state <= FINAL_2;
					
					end
					else begin
						FIFO_output_WriteEn_in <= 0;
					end	
				end
				
				FINAL_2: begin
					if(!stall) begin

						FIFO_output_WriteEn_in 			<= 1;
						FIFO_output_Data_in[512+57:512] <= 0;
						FIFO_output_Data_in[511:0]      <= {1'b1,511'b0}; //fence

						state <= IDLE;
					
					end
					else begin
						FIFO_output_WriteEn_in <= 0;
					end	
				
				
				
				end
		
				
			endcase
		end
	end
	
	
	Top top(
		.Clk_32UI(CLK_200M),
		.reset_n(batch_reset_n),
		.stall(stall), 
		
		//RAM for reads
		.load_valid(load_valid),
		.load_data(load_data),
		.batch_size(batch_size),
		.read_load_done(read_load_done),
		
		//memory requests / responses
		.DRAM_valid(DRAM_valid),
		.addr_k(addr_k), .addr_l(addr_l),
		.DRAM_read_num(DRAM_read_num),
		
		.DRAM_get(DRAM_get), //[important] need testing
		.cnt_a0 (CL_1_200M[31:0]),		.cnt_a1 (CL_1_200M[95:64]),		.cnt_a2 (CL_1_200M[159:128]),	.cnt_a3 (CL_1_200M[223:192]),
		.cnt_b0 (CL_1_200M[319:256]),	.cnt_b1 (CL_1_200M[383:320]),	.cnt_b2 (CL_1_200M[447:384]),	.cnt_b3 (CL_1_200M[511:448]),
		.cntl_a0(CL_2_200M[31:0]),		.cntl_a1(CL_2_200M[95:64]),		.cntl_a2(CL_2_200M[159:128]),	.cntl_a3(CL_2_200M[223:192]),
		.cntl_b0(CL_2_200M[319:256]),	.cntl_b1(CL_2_200M[383:320]),	.cntl_b2(CL_2_200M[447:384]),	.cntl_b3(CL_2_200M[511:448]),
		
		.output_request(output_request_200M),
		.output_permit(output_permit),
		
		.output_data(output_data_200M),
		.output_valid(output_valid_200M),
		.output_finish (output_finish_200M)		
	);

endmodule

