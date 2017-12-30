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

	(* preserve *) reg stall_A /* synthesis preserve */;
	(* preserve *) reg stall_B /* synthesis preserve */;
	(* preserve *) reg stall_C /* synthesis preserve */;
	(* preserve *) reg stall_D /* synthesis preserve */;
	
	always@(posedge CLK_200M) begin
		stall_A <= spl_tx_rd_almostfull | spl_tx_wr_almostfull;
		stall_B <= spl_tx_rd_almostfull | spl_tx_wr_almostfull;
		stall_C <= spl_tx_rd_almostfull | spl_tx_wr_almostfull;
		stall_D <= spl_tx_rd_almostfull | spl_tx_wr_almostfull;
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
	
	wire FIFO_request_ReadEn_in = 1'b1;
	wire FIFO_output_ReadEn_in = 1'b1;
	//output FIFO
	reg [512+57:0] FIFO_output_Data_in;
	reg FIFO_output_WriteEn_in;
	
	// address
	aFIFO_output #(.DATA_WIDTH(58), .ADDRESS_WIDTH(2)) FIFO_output_addr(
		.Clear_in(!core_start),
		.stall(stall_A),
		
		//200M
		.Data_in(FIFO_output_Data_in[512+57:512]),
		.WriteEn_in(FIFO_output_WriteEn_in),
		.Full_out(),
		.WClk(CLK_200M),
		
		//400M
		.Data_out(FIFO_output_Data_out[512+57:512]),
		.Data_valid(FIFO_output_Data_valid),
		.ReadEn_in(FIFO_output_ReadEn_in),
		.Empty_out(),
		.RClk(CLK_400M)
	);
	
	// 511:384
	aFIFO_output #(.DATA_WIDTH(128), .ADDRESS_WIDTH(2)) FIFO_output_511_384(
		.Clear_in(!core_start),
		.stall(stall_A),
		
		//200M
		.Data_in(FIFO_output_Data_in[511:384]),
		.WriteEn_in(FIFO_output_WriteEn_in),
		.Full_out(),
		.WClk(CLK_200M),
		
		//400M
		.Data_out(FIFO_output_Data_out[511:384]),
		.Data_valid(),
		.ReadEn_in(FIFO_output_ReadEn_in),
		.Empty_out(),
		.RClk(CLK_400M)
	);
	
	// 383:256
	aFIFO_output #(.DATA_WIDTH(128), .ADDRESS_WIDTH(2)) FIFO_output_383_256(
		.Clear_in(!core_start),
		.stall(stall_A),
		
		//200M
		.Data_in(FIFO_output_Data_in[383:256]),
		.WriteEn_in(FIFO_output_WriteEn_in),
		.Full_out(),
		.WClk(CLK_200M),
		
		//400M
		.Data_out(FIFO_output_Data_out[383:256]),
		.Data_valid(),
		.ReadEn_in(FIFO_output_ReadEn_in),
		.Empty_out(),
		.RClk(CLK_400M)
	);
	
	// 255:128
	aFIFO_output #(.DATA_WIDTH(128), .ADDRESS_WIDTH(2)) FIFO_output_255_128(
		.Clear_in(!core_start),
		.stall(stall_A),
		
		//200M
		.Data_in(FIFO_output_Data_in[255:128]),
		.WriteEn_in(FIFO_output_WriteEn_in),
		.Full_out(),
		.WClk(CLK_200M),
		
		//400M
		.Data_out(FIFO_output_Data_out[255:128]),
		.Data_valid(),
		.ReadEn_in(FIFO_output_ReadEn_in),
		.Empty_out(),
		.RClk(CLK_400M)
	);
	
	// 127:0
	aFIFO_output #(.DATA_WIDTH(128), .ADDRESS_WIDTH(2)) FIFO_output_127_0(
		.Clear_in(!core_start),
		.stall(stall_A),
		
		//200M
		.Data_in(FIFO_output_Data_in[127:0]),
		.WriteEn_in(FIFO_output_WriteEn_in),
		.Full_out(),
		.WClk(CLK_200M),
		
		//400M
		.Data_out(FIFO_output_Data_out[127:0]),
		.Data_valid(),
		.ReadEn_in(FIFO_output_ReadEn_in),
		.Empty_out(),
		.RClk(CLK_400M)
	);
	
	//response FIFO k
	
	wire FIFO_response_k_Empty_out_511_384, FIFO_response_l_Empty_out_511_384;
	wire FIFO_response_k_Empty_out_383_256, FIFO_response_l_Empty_out_383_256;
	wire FIFO_response_k_Empty_out_255_128, FIFO_response_l_Empty_out_255_128;
	wire FIFO_response_k_Empty_out_127_0, 	FIFO_response_l_Empty_out_127_0;
	
	wire both_not_empty_511_384 = (!FIFO_response_k_Empty_out_511_384) 	& (!FIFO_response_l_Empty_out_511_384);
	wire both_not_empty_383_256 = (!FIFO_response_k_Empty_out_383_256) 	& (!FIFO_response_l_Empty_out_383_256);
	wire both_not_empty_255_128 = (!FIFO_response_k_Empty_out_255_128) 	& (!FIFO_response_l_Empty_out_255_128);
	wire both_not_empty_127_0 	= (!FIFO_response_k_Empty_out_127_0) 	& (!FIFO_response_l_Empty_out_127_0);
	
	wire FIFO_response_k_Data_valid_511_384, 	FIFO_response_l_Data_valid_511_384;
	// wire FIFO_response_k_Data_valid_383_256, 	FIFO_response_l_Data_valid_383_256;	
	// wire FIFO_response_k_Data_valid_255_128, 	FIFO_response_l_Data_valid_255_128;	
	// wire FIFO_response_k_Data_valid_127_0, 		FIFO_response_l_Data_valid_127_0;
	
	wire both_valid = FIFO_response_k_Data_valid_511_384 	& FIFO_response_l_Data_valid_511_384;

	
	wire [511:0] FIFO_response_k_Data_out, FIFO_response_l_Data_out;
	
	
	//response FIFO k [511:384]
	aFIFO #(.DATA_WIDTH(128), .ADDRESS_WIDTH(2)) FIFO_response_k_511_384(
		.Clear_in(!core_start),
		
		//400M
		.Data_in(FIFO_response_k_Data_in[511:384]),
		.WriteEn_in(FIFO_response_k_WriteEn_in),
		.Full_out(),
		.WClk(CLK_400M),
		
		//200M
		.Data_out(FIFO_response_k_Data_out[511:384]),
		.Data_valid(FIFO_response_k_Data_valid_511_384),
		
		//read out the results a pair at a time
		.ReadEn_in(both_not_empty_511_384), 
		.Empty_out(FIFO_response_k_Empty_out_511_384),
		.RClk(CLK_200M)
	);
	
	//response FIFO k [383:256]
	aFIFO #(.DATA_WIDTH(128), .ADDRESS_WIDTH(2)) FIFO_response_k_383_256(
		.Clear_in(!core_start),
		
		//400M
		.Data_in(FIFO_response_k_Data_in[383:256]),
		.WriteEn_in(FIFO_response_k_WriteEn_in),
		.Full_out(),
		.WClk(CLK_400M),
		
		//200M
		.Data_out(FIFO_response_k_Data_out[383:256]),
		.Data_valid(),
		
		//read out the results a pair at a time
		.ReadEn_in(both_not_empty_383_256), 
		.Empty_out(FIFO_response_k_Empty_out_383_256),
		.RClk(CLK_200M)
	);
	
	//response FIFO k [255:128]
	aFIFO #(.DATA_WIDTH(128), .ADDRESS_WIDTH(2)) FIFO_response_k_255_128(
		.Clear_in(!core_start),
		
		//400M
		.Data_in(FIFO_response_k_Data_in[255:128]),
		.WriteEn_in(FIFO_response_k_WriteEn_in),
		.Full_out(),
		.WClk(CLK_400M),
		
		//200M
		.Data_out(FIFO_response_k_Data_out[255:128]),
		.Data_valid(), //one valid is enough
		
		//read out the results a pair at a time
		.ReadEn_in(both_not_empty_255_128), 
		.Empty_out(FIFO_response_k_Empty_out_255_128),
		.RClk(CLK_200M)
	);
	
	//response FIFO k [127:0]
	aFIFO #(.DATA_WIDTH(128), .ADDRESS_WIDTH(2)) FIFO_response_k_127_0(
		.Clear_in(!core_start),
		
		//400M
		.Data_in(FIFO_response_k_Data_in[127:0]),
		.WriteEn_in(FIFO_response_k_WriteEn_in),
		.Full_out(),
		.WClk(CLK_400M),
		
		//200M
		.Data_out(FIFO_response_k_Data_out[127:0]),
		.Data_valid(), //one valid is enough
		
		//read out the results a pair at a time
		.ReadEn_in(both_not_empty_127_0), 
		.Empty_out(FIFO_response_k_Empty_out_127_0),
		.RClk(CLK_200M)
	);
	
	//response FIFO l 511:384
	aFIFO #(.DATA_WIDTH(128), .ADDRESS_WIDTH(2)) FIFO_response_l_511_384(
		.Clear_in(!core_start),
		
		//400M
		.Data_in(FIFO_response_l_Data_in[511:384]),
		.WriteEn_in(FIFO_response_l_WriteEn_in),
		.Full_out(),
		.WClk(CLK_400M),
		
		//200M
		.Data_out(FIFO_response_l_Data_out[511:384]),
		.Data_valid(FIFO_response_l_Data_valid_511_384),
		.ReadEn_in(both_not_empty_511_384), 
		.Empty_out(FIFO_response_l_Empty_out_511_384),
		.RClk(CLK_200M)
	);
	
	//response FIFO l 383:256
	aFIFO #(.DATA_WIDTH(128), .ADDRESS_WIDTH(2)) FIFO_response_l_383_256(
		.Clear_in(!core_start),
		
		//400M
		.Data_in(FIFO_response_l_Data_in[383:256]),
		.WriteEn_in(FIFO_response_l_WriteEn_in),
		.Full_out(),
		.WClk(CLK_400M),
		
		//200M
		.Data_out(FIFO_response_l_Data_out[383:256]),
		.Data_valid(),
		.ReadEn_in(both_not_empty_383_256), 
		.Empty_out(FIFO_response_l_Empty_out_383_256),
		.RClk(CLK_200M)
	);
	
	//response FIFO l 255:128
	aFIFO #(.DATA_WIDTH(128), .ADDRESS_WIDTH(2)) FIFO_response_l_255_128(
		.Clear_in(!core_start),
		
		//400M
		.Data_in(FIFO_response_l_Data_in[255:128]),
		.WriteEn_in(FIFO_response_l_WriteEn_in),
		.Full_out(),
		.WClk(CLK_400M),
		
		//200M
		.Data_out(FIFO_response_l_Data_out[255:128]),
		.Data_valid(),
		.ReadEn_in(both_not_empty_255_128), 
		.Empty_out(FIFO_response_l_Empty_out_255_128),
		.RClk(CLK_200M)
	);
	
	//response FIFO l 127:0
	aFIFO #(.DATA_WIDTH(128), .ADDRESS_WIDTH(2)) FIFO_response_l_127_0(
		.Clear_in(!core_start),
		
		//400M
		.Data_in(FIFO_response_l_Data_in[127:0]),
		.WriteEn_in(FIFO_response_l_WriteEn_in),
		.Full_out(),
		.WClk(CLK_400M),
		
		//200M
		.Data_out(FIFO_response_l_Data_out[127:0]),
		.Data_valid(),
		.ReadEn_in(both_not_empty_127_0), 
		.Empty_out(FIFO_response_l_Empty_out_127_0),
		.RClk(CLK_200M)
	);
	
	reg [57:0] FIFO_request_Data_in_1, FIFO_request_Data_in_2;
	reg FIFO_request_WriteEn_in_2;
	wire [`READ_NUM_WIDTH-1:0] DRAM_read_num, DRAM_read_num_out;
	reg [`READ_NUM_WIDTH-1:0] DRAM_read_num_q; 
	always@(posedge CLK_200M) if(!stall_A)DRAM_read_num_q <= DRAM_read_num;
	// request FIFO addr k
	aFIFO_2w_1r #(.DATA_WIDTH(58+`READ_NUM_WIDTH), .ADDRESS_WIDTH(2)) FIFO_request(
		.Clear_in(!core_start),
		.stall(stall_A),
		
		//200M
		.Data_in_1({DRAM_read_num_q, FIFO_request_Data_in_1}),
		.Data_in_2({DRAM_read_num_q, FIFO_request_Data_in_2}),
		.WriteEn_in_2(FIFO_request_WriteEn_in_2),
		.Full_out(),
		.WClk(CLK_200M),
		
		//400M
		.Data_out({DRAM_read_num_out, FIFO_request_Data_out}),
		.Data_valid(FIFO_request_Data_valid),
		.ReadEn_in(FIFO_request_ReadEn_in),
		.Empty_out(),
		.RClk(CLK_400M)
	);
	
	
	//==========================================================================
	
	// 200M domain
	
	

	
	reg [57:0] hand_ptr;
	reg [57:0] input_base;
	reg [57:0] output_base;
	reg [57:0] BWT_base;
	
	always@(posedge CLK_200M) begin
		hand_ptr <= io_src_ptr + 50348031; //50331648 + 16384 - 1
		input_base <= io_src_ptr + 50348032; //50331648 + 16384
		output_base <= io_dst_ptr;
		BWT_base <= io_src_ptr;
	end
	
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
					output_addr<= output_base;
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
					if(!stall_A) begin
						FIFO_request_Data_in_1 <= hand_ptr;
						FIFO_request_Data_in_2 <= hand_ptr;
						FIFO_request_WriteEn_in_2 <= 1;
					
						state <= POLLING_2;
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
					if(!stall_A) begin
						if(load_ptr < CL_num) begin
						
							//send out two identical request for compatibility with other modules
							FIFO_request_Data_in_1 <= input_base + load_ptr;
							FIFO_request_Data_in_2 <= input_base + load_ptr;
							FIFO_request_WriteEn_in_2 <= 1;
						
							load_ptr <= load_ptr + 1;
						end
						else begin
							FIFO_request_WriteEn_in_2 <= 0;
						end
						
						//control
						if(read_load_done) begin
							state <= RUN;
						end
					
					end 
					
					//memory responses
					if(both_valid) begin
						load_valid <= 1;
						load_data <= FIFO_response_k_Data_out; //two responses should be the same
					end
					else begin
						load_valid <= 0;
					end				
				end
				
				RUN: begin
					if(!stall_A) begin
						if(!output_request_200M) begin
							//send out request
							
							FIFO_request_Data_in_1 <= BWT_base + addr_k[31:4];
							FIFO_request_Data_in_2 <= BWT_base + addr_l[31:4];
							FIFO_request_WriteEn_in_2 <= DRAM_valid;
							
						end
						
						else begin
							FIFO_request_WriteEn_in_2 <= 0;
							output_permit <= 1;
							state <= OUTPUT;
						end
					end
										
					//get response
					DRAM_get <= both_valid;
					CL_1_200M <= FIFO_response_k_Data_out;
					CL_2_200M <= FIFO_response_l_Data_out;
				end
				
				OUTPUT: begin
					if(!stall_A) begin
						if(!output_finish_200M) begin
							FIFO_output_WriteEn_in <= output_valid_200M;
							FIFO_output_Data_in[512+57:512] <= output_addr;
							FIFO_output_Data_in[511:0]      <= output_data_200M;
						
							if(output_valid_200M) output_addr <= output_addr + 1;
						end
						else begin
							FIFO_output_WriteEn_in 			<= 1;
							FIFO_output_Data_in[512+57:512] <= 0;
							FIFO_output_Data_in[511:0]      <= {1'b1,511'b0}; //fence
							state <= FINAL;					
						end
					end				
				end
				
				FINAL : begin
					if(!stall_A) begin
						FIFO_output_WriteEn_in <= 1;
						FIFO_output_Data_in[512+57:512] <= hand_ptr;
						FIFO_output_Data_in[511:480]    <= 16;
						FIFO_output_Data_in[479:0]    <= 0;
						state <= FINAL_2;
					
					end
				end
				
				FINAL_2: begin
					if(!stall_A) begin

						FIFO_output_WriteEn_in 			<= 1;
						FIFO_output_Data_in[512+57:512] <= 0;
						FIFO_output_Data_in[511:0]      <= {1'b1,511'b0}; //fence

						state <= IDLE;
					
					end
				end
		
				
			endcase
		end
	end
	
	
	Top top(
		.Clk_32UI(CLK_200M),
		.reset_n(batch_reset_n),
		.stall_B(stall_B), 
		.stall_C(stall_C), 
		.stall_D(stall_D), 
		.stall_E(stall_B), 
		.stall_F(stall_C), 
		
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

