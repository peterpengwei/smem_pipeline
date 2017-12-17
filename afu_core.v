// core for pipeline SMEM kernel
// Licheng 12.5
`define CL 512
`define MAX_READ 256
`define READ_NUM_WIDTH 8

module afu_core(
	input  wire                             CLK_400M,
    input  wire                             reset_n,
    
	//---------------------------------------------------
    //input  wire                             spl_enable,
	input  wire 							core_start,
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
    output reg                              cor_tx_done_valid,
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
	parameter IDLE = 0;
	parameter POLLING = 1;
	parameter CHECK_POLLING = 2;
	parameter LOAD_400M = 3;
	parameter LOAD_200M = 4;
	parameter LOAD_200M_Q= 5;
	parameter RUN_1 = 6;
	parameter RUN_2 = 7;
	parameter OUTPUT_1 = 8;
	parameter OUTPUT_2 = 9;
	parameter FENCE = 10;
	parameter FINAL = 11;
	parameter FENCE_2 = 12;
	
	
	wire [57:0] hand_ptr = io_src_ptr + 50331648 + 16384 - 1;
	wire [57:0] input_base = io_src_ptr + 50331648 + 16384;
	wire [57:0] output_base = io_dst_ptr;
	wire [57:0] BWT_base = io_src_ptr;
	reg  [57:0] output_addr;
	
	reg polling_tag;
	wire BWT_read_tag_0 = io_rx_data[480];
	wire BWT_read_tag_1 = io_rx_data[482];
	
	//note batch size must be 1 bit wider than memory. e.g. 256 reads takes 8 bits to present.
	wire 	[`READ_NUM_WIDTH+1 - 1:0] batch_size_temp = io_rx_data[`READ_NUM_WIDTH+1 - 1 + 448:448];	
	reg 	[`READ_NUM_WIDTH+1 - 1:0] batch_size;
	
	//[licheng] very dangerous here.
	wire 	[`READ_NUM_WIDTH+1+2 - 1:0] CL_num = batch_size << 2;
	reg 	[`READ_NUM_WIDTH+1+2 - 1:0] load_ptr;
	reg 	[`READ_NUM_WIDTH+1+2 - 1:0] RAM_400M_ptr;
	reg 	[`READ_NUM_WIDTH+1+2 - 1:0] RAM_200M_ptr;
	reg load_valid;
	reg 	[`CL-1:0] load_data;
	
	reg batch_reset_n;
	reg 	[`CL-1:0] RAM_400M[`MAX_READ*4 - 1 :0]; // one read corresponds to 4 CLs.
	
	wire [31:0] addr_k_400M, addr_l_400M;
	reg [31:0] addr_l_400M_reg;
	reg addr_l_400M_valid;
	
	wire FIFO_request_full, FIFO_response_full, FIFO_output_full;
	wire FIFO_request_empty, FIFO_response_empty, FIFO_output_empty;
	wire FIFO_request_rd_en;
	//reg FIFO_output_rd_en;
	wire FIFO_output_rd_en;
	
	wire output_request_200M;
	reg output_permit;
	wire output_finish_200M;
	wire [511:0] output_data_200M, output_data_400M;
	wire output_valid_200M;
	
	reg [5:0] state_BWA;
	reg debug1, debug2, debug3, debug4;
	wire FIFO_request_valid;
	
	
	// central controller && TX_RD
	
	//[important] for the control of FIFO_request
	assign FIFO_request_rd_en = ((state_BWA == RUN_1) & (!FIFO_request_empty) & (!spl_tx_rd_almostfull));
	assign FIFO_output_rd_en = ((state_BWA == OUTPUT_1) & (!FIFO_output_empty) & (!spl_tx_wr_almostfull));
	
	always@(posedge CLK_400M) begin
		if(!reset_n) begin
			
			cor_tx_rd_valid <= 0;
			cor_tx_rd_addr <= 0;
			cor_tx_rd_len <= 0;
			batch_size <= 0;
			polling_tag <= 0;
			load_ptr <= 0;
			batch_reset_n <= 0;
			RAM_400M_ptr <= 0;
			RAM_200M_ptr <= 0;
			//FIFO_request_rd_en <= 0;
			// FIFO_output_rd_en <= 0;
			addr_l_400M_reg <= 0;
			addr_l_400M_valid<= 0;
			output_permit <= 0;
			
			cor_tx_wr_valid <= 0;
			cor_tx_dsr_valid <= 0;
			cor_tx_fence_valid <= 0;
			cor_tx_done_valid <= 0;
			cor_tx_wr_addr <= 0; 
			cor_tx_wr_len <= 0; 
			cor_tx_data <= 0;
			
			output_addr <= 0;
			
			state_BWA <= IDLE;
		end
		else begin
			case(state_BWA)
				// IDLE ---------------------
				IDLE: begin
					if(core_start) begin
						cor_tx_rd_valid <= 0;
						cor_tx_rd_addr <= 0;
						cor_tx_rd_len <= 0;
						batch_size <= 0;
						//polling_tag <= 0;
						load_ptr <= 0;
						batch_reset_n <= 0;
						RAM_400M_ptr <= 0;
						RAM_200M_ptr <= 0;
						// FIFO_output_rd_en <= 0;
						addr_l_400M_reg <= 0;
						addr_l_400M_valid<= 0;
						output_permit <= 0;
						output_addr <= 0;
						
						cor_tx_wr_valid <= 0; 
						cor_tx_wr_addr <= 0;
						cor_tx_data <= 0;	
						cor_tx_fence_valid <= 0;
						state_BWA <= POLLING;
					end
					else begin
						state_BWA <= IDLE;
					end
				end
				
				// POLLING -------------------
				POLLING: begin
					batch_reset_n <= 1;
					if(!spl_tx_rd_almostfull) begin
						cor_tx_rd_valid <= 1;
						cor_tx_rd_addr <= hand_ptr;
						cor_tx_rd_len <= 1;
						state_BWA <= CHECK_POLLING;
					end
					else begin
						cor_tx_rd_valid <= 0;
						cor_tx_rd_addr <= 0;
						cor_tx_rd_len <= 0;
						state_BWA <= POLLING;					
					end
				end
				
				// CHECK_POLLING ----------------------
				CHECK_POLLING: begin
					cor_tx_rd_valid <= 0;
					cor_tx_rd_addr <= 0;
					cor_tx_rd_len <= 0;
						
					if(io_rx_rd_valid) begin
						if(BWT_read_tag_0 && (polling_tag==0)) begin
							state_BWA <= LOAD_400M;
							batch_size <= batch_size_temp;
							polling_tag <= 1;
						end
						else if(BWT_read_tag_1 && (polling_tag==1)) begin
							state_BWA <= LOAD_400M;
							batch_size <= batch_size_temp;
							polling_tag <= 0;
						end
						else begin
							state_BWA <= POLLING;
						end
					end
				end
				
				// LOAD 400M -----------------------
				// load all reads into 400M fields
				LOAD_400M : begin
					
					if(load_ptr < CL_num) begin	
						if(!spl_tx_rd_almostfull) begin
							cor_tx_rd_valid <= 1;
							cor_tx_rd_addr <= input_base + load_ptr;
							load_ptr <= load_ptr + 1;
							cor_tx_rd_len <= 1;
						end
						else begin
							cor_tx_rd_valid <= 0;
							cor_tx_rd_addr <= 0;
							cor_tx_rd_len <= 0;
						end
					end
					else begin
						cor_tx_rd_valid <= 0;
						cor_tx_rd_addr <= 0;
						cor_tx_rd_len <= 0;
							
						if(load_ptr == CL_num && RAM_400M_ptr == CL_num) begin
							state_BWA <= LOAD_200M;
						end
						else begin
							state_BWA <= LOAD_400M;
						end
					end
					
					if(io_rx_rd_valid) begin
						RAM_400M[RAM_400M_ptr] <= io_rx_data;
						RAM_400M_ptr <= RAM_400M_ptr + 1;
					end
				end
				
				// LOAD_200M -------------------------
				// transfer 400M reads to 200M reads
				LOAD_200M: begin
					if(RAM_200M_ptr < CL_num) begin
						load_valid <= 1;
						load_data <= RAM_400M[RAM_200M_ptr];
						RAM_200M_ptr <= RAM_200M_ptr + 1;
						state_BWA <= LOAD_200M_Q;
					end
					else begin
						load_valid <= 0;
						load_data <= 0;

						addr_l_400M_valid <= 0;
						state_BWA <= RUN_1;
					end
				end
				
				LOAD_200M_Q: begin
					state_BWA <= LOAD_200M;
				end
				
				// RUN: send out read request -------------------------------
				RUN_1: begin
					if(!output_request_200M) begin
						if(!FIFO_request_empty && !spl_tx_rd_almostfull)begin
							// wire FIFO_request_rd_en <= 1;
							state_BWA <= RUN_2;
						end
						else begin						
							state_BWA <= RUN_1;
						end
						
						// no matter of almostfull condition, must send out addr_l if available.
						if(addr_l_400M_valid) begin
							cor_tx_rd_valid <= 1;
							cor_tx_rd_addr <= BWT_base + addr_l_400M_reg[31:4];
							cor_tx_rd_len <= 1;	
							
							addr_l_400M_valid <= 0;
						end
						else begin
							cor_tx_rd_valid <= 0;
							cor_tx_rd_addr <= 0;
							cor_tx_rd_len <= 0;	
							
							addr_l_400M_valid <= 0;
						end
					
					end
					else begin // all reads done, ready for output
						cor_tx_rd_valid <= 0;
						cor_tx_rd_addr <= 0;
						cor_tx_rd_len <= 0;	
						addr_l_400M_valid <= 0;
						output_permit <= 1;
						// FIFO_output_rd_en <= 0;
						
						output_addr <= 0;
						
						state_BWA <= OUTPUT_1;
					end
				end
				
				RUN_2: begin					
					if(FIFO_request_valid) begin
						cor_tx_rd_valid <= 1;
						cor_tx_rd_addr <= BWT_base + addr_k_400M[31:4];
						cor_tx_rd_len <= 1;

						addr_l_400M_reg <= addr_l_400M;
						addr_l_400M_valid<= 1;
						
						state_BWA <= RUN_1;
					end
					
				end
				
				// OUTPUT -------------------------------
				
				OUTPUT_1: begin
					if(!output_finish_200M) begin // cross clk domain
						if(!FIFO_output_empty) begin
							state_BWA <= OUTPUT_2;
						end
					end
					else begin
						state_BWA <= FENCE;
					end
					
					cor_tx_wr_valid <= 0; 
					cor_tx_wr_addr <= 0;
					cor_tx_data <= 0;
				end
				
				OUTPUT_2: begin
					// FIFO_output_rd_en <= 0;
					
					if(~spl_tx_wr_almostfull) begin
						cor_tx_wr_valid <= 1'b1; 
						cor_tx_wr_addr <= output_base + output_addr;
						cor_tx_data <= output_data_400M;

						output_addr <= output_addr + 1;
						
						state_BWA <= OUTPUT_1;
					end
				end
				
				FENCE : begin
					if (~spl_tx_wr_almostfull) begin
                        cor_tx_wr_valid <= 1'b1;
                        cor_tx_fence_valid <= 1'b1;
                        state_BWA <= FINAL;

                    end
				end
				
				FINAL: begin
					if (~spl_tx_wr_almostfull) begin
						cor_tx_fence_valid <= 1'b0;
						
                        cor_tx_wr_valid <= 1'b1;
                        cor_tx_dsr_valid <= 1'b0;
                        cor_tx_wr_len <= 6'h1;
                        cor_tx_wr_addr <= hand_ptr;
                        cor_tx_data[511:480] <= 16;
                        cor_tx_data[479:0] <= 0;
                    
				
						state_BWA <= FENCE_2;

					end
				end
				
				FENCE_2: begin
					if (~spl_tx_wr_almostfull) begin
						cor_tx_dsr_valid <= 1'b0;
                        cor_tx_wr_len <= 6'h1;
                        cor_tx_wr_addr <= hand_ptr;
                        cor_tx_data <= 0;
						
                        cor_tx_wr_valid <= 1'b1;
                        cor_tx_fence_valid <= 1'b1;
                        state_BWA <= IDLE;

                    end
					
				end
				
				
			endcase
		end
	end
	
	
	
	wire [511:0] CL_1_200M, CL_2_200M;
	reg push_response_FIFO;
	reg [5:0] state_RD_RX;
	parameter RD_RX_IDLE = 0;
	parameter RD_RX_RUN_1 = 1;
	parameter RD_RX_RUN_2 = 2;
	
	//wire push_response_FIFO = (state_RD_RX == RD_RX_RUN_2) & io_rx_rd_valid;
	
	reg [511:0] CL_1;
	reg [511:0] CL_2;
	//wire [511:0] CL_2 = push_response_FIFO ? io_rx_data : 0;
	

	
	//Controller for memory responses
	always@(posedge CLK_400M) begin
		if(!reset_n) begin
			CL_1 <= 0;
			CL_2 <= 0;
			push_response_FIFO<= 0;
			
			
			state_RD_RX <= RD_RX_IDLE;
			
		end
		else begin
			case(state_RD_RX)
				RD_RX_IDLE: begin
					if(state_BWA == RUN_1 || state_BWA == RUN_2) begin
						CL_1 <= 0;
						CL_2 <= 0;
						push_response_FIFO <= 0;
						state_RD_RX <= RD_RX_RUN_1;
					end
					else begin
						state_RD_RX <= RD_RX_IDLE;
					end
				end
				
				//[important] No matter of FIFO condition, must push data into FIFO
				RD_RX_RUN_1: begin
					if(!output_request_200M) begin
						if(io_rx_rd_valid) begin
							CL_1 <= io_rx_data;
							CL_2 <=  0;
							push_response_FIFO <= 0;
							
							state_RD_RX <= RD_RX_RUN_2; // first responses, wait for 2nd
						end
						else begin
							CL_1 <= 0;
							CL_2 <= 0;
							push_response_FIFO <= 0;
							
							state_RD_RX <= RD_RX_RUN_1;
						end
					end
					else begin
						CL_1 <= 0;
						CL_2 <= 0;
						push_response_FIFO <= 0;
						state_RD_RX <= RD_RX_IDLE; // wait for next batch of reads
					end
				end
				
				RD_RX_RUN_2: begin
					if(!output_request_200M) begin
						if(io_rx_rd_valid) begin
							CL_2 <= io_rx_data;
							push_response_FIFO <= 1;
							
							state_RD_RX <= RD_RX_RUN_1; // 2nd responses, wait for another round
						end
						else begin
							CL_2 <= 0;
							push_response_FIFO <= 0;
							
							state_RD_RX <= RD_RX_RUN_2;
						end
					end
					else begin
						CL_1 <= 0;
						CL_2 <= 0;
						push_response_FIFO <= 0;
						state_RD_RX <= RD_RX_IDLE; // wait for next batch of reads

					
					end
				end
	
			endcase
		end
	end
	
	
	//----------------------------
	reg CLK_200M;
	always@(posedge CLK_400M) begin
		if(!reset_n) begin
			CLK_200M <= 0;
		end
		else begin
		
			CLK_200M <= !CLK_200M;
		end
	end
	
	
	wire [31:0] addr_k, addr_l;
	wire  DRAM_valid;
	wire DRAM_get;
	
	// request FIFO
	aFIFO #(.DATA_WIDTH(64), .ADDRESS_WIDTH(4)) FIFO_request(
		.Clear_in(!core_start),
		
		//200M
		.Data_in({addr_k, addr_l}),
		.WriteEn_in(DRAM_valid),
		.Full_out(FIFO_request_full),
		.WClk(CLK_200M),
		
		//400M
		.Data_out({addr_k_400M,addr_l_400M}),
		.Data_valid(FIFO_request_valid),
		.ReadEn_in(FIFO_request_rd_en),
		.Empty_out(FIFO_request_empty),
		.RClk(CLK_400M)
	);
	
	//response FIFO
	aFIFO #(.DATA_WIDTH(1024), .ADDRESS_WIDTH(4)) FIFO_response(
		.Clear_in(!core_start),
		
		//400M
		.Data_in({CL_2, CL_1}),
		.WriteEn_in(push_response_FIFO),
		.Full_out(),
		.WClk(CLK_400M),
		
		//200M
		.Data_out({CL_2_200M, CL_1_200M}),
		.Data_valid(DRAM_get),
		.ReadEn_in(!FIFO_response_empty & reset_n), //[important] need testing
		.Empty_out(FIFO_response_empty),
		.RClk(CLK_200M)
	);
	
	//output FIFO
	aFIFO #(.DATA_WIDTH(512), .ADDRESS_WIDTH(4)) FIFO_output(
		.Clear_in(!core_start),
		
		//200M
		.Data_in(output_data_200M),
		.WriteEn_in(output_valid_200M),
		.Full_out(FIFO_output_full),
		.WClk(CLK_200M),
		
		//400M
		.Data_out(output_data_400M),
		.ReadEn_in(FIFO_output_rd_en),
		.Empty_out(FIFO_output_empty),
		.RClk(CLK_400M)
	);
	
	wire stall = spl_tx_rd_almostfull | spl_tx_wr_almostfull | FIFO_request_full | FIFO_output_full;
	
	Top top(
		.Clk_32UI(CLK_200M),
		.reset_n(batch_reset_n),
		.stall(stall), // [important] to be tested
		
		//RAM for reads
		.load_valid(load_valid),
		.load_data(load_data),
		.batch_size(batch_size),
		
		//memory requests / responses
		.DRAM_valid(DRAM_valid),
		.addr_k(addr_k), .addr_l(addr_l),
		
		.DRAM_get(DRAM_get), //[important] need testing
		.cnt_a0 (CL_1_200M[31:0]),		.cnt_a1 (CL_1_200M[95:64]),		.cnt_a2 (CL_1_200M[159:128]),	.cnt_a3 (CL_1_200M[223:192]),
		.cnt_b0 (CL_1_200M[319:256]),	.cnt_b1 (CL_1_200M[383:320]),	.cnt_b2 (CL_1_200M[447:384]),	.cnt_b3 (CL_1_200M[511:448]),
		.cntl_a0(CL_2_200M[31:0]),		.cntl_a1(CL_2_200M[95:64]),		.cntl_a2(CL_2_200M[159:128]),	.cntl_a3(CL_2_200M[223:192]),
		.cntl_b0(CL_2_200M[319:256]),	.cntl_b1(CL_2_200M[383:320]),	.cntl_b2(CL_2_200M[447:384]),	.cntl_b3(CL_2_200M[511:448]),
		
		.output_request(output_request_200M),
		.output_permit(output_permit),
		
		.output_data(output_data_200M),
		.output_valid(output_valid_200M),
		.output_finish (output_finish_200M),
		
		.backward_i_q_test(backward_i_q_test), 
		.backward_j_q_test(backward_j_q_test)
		
	);
	


endmodule



//==========================================
// Function : Asynchronous FIFO (w/ 2 asynchronous clocks).
// Coder    : Alex Claros F.
// Date     : 15/May/2005.
// Notes    : This implementation is based on the article 
//            'Asynchronous FIFO in Virtex-II FPGAs'
//            writen by Peter Alfke. This TechXclusive 
//            article can be downloaded from the
//            Xilinx website. It has some minor modifications.
//=========================================

module aFIFO
  #(parameter    DATA_WIDTH    = 65,
                 ADDRESS_WIDTH = 2,
                 FIFO_DEPTH    = (1 << ADDRESS_WIDTH))
     //Reading port
    (output reg  [DATA_WIDTH-1:0]        Data_out, 
	 output reg  						 Data_valid,
     output reg                          Empty_out,
     input wire                          ReadEn_in,
     input wire                          RClk,        
     //Writing port.	 
     input wire  [DATA_WIDTH-1:0]        Data_in,  
     output reg                          Full_out,
     input wire                          WriteEn_in,
     input wire                          WClk,
	 
     input wire                          Clear_in);

    /////Internal connections & variables//////
    reg   [DATA_WIDTH-1:0]              Mem [FIFO_DEPTH-1:0];
    wire  [ADDRESS_WIDTH-1:0]           pNextWordToWrite, pNextWordToRead;
    wire                                EqualAddresses;
    wire                                NextWriteAddressEn, NextReadAddressEn;
    wire                                Set_Status, Rst_Status;
    reg                                 Status;
    wire                                PresetFull, PresetEmpty;
    
    //////////////Code///////////////
    //Data ports logic:
    //(Uses a dual-port RAM).
    //'Data_out' logic:
    always @ (posedge RClk) begin
		if(Clear_in) begin
			Data_valid <= 0;
		
		end
		else begin
			if (ReadEn_in & !Empty_out) begin
				Data_out <= Mem[pNextWordToRead];
				Data_valid <= 1;
			end
			else begin
				Data_valid <= 0;
			end
		end
	end
			//'Data_in' logic:
    always @ (posedge WClk)
        if (WriteEn_in & !Full_out)
            Mem[pNextWordToWrite] <= Data_in;

    //Fifo addresses support logic: 
    //'Next Addresses' enable logic:
    assign NextWriteAddressEn = WriteEn_in & ~Full_out;
    assign NextReadAddressEn  = ReadEn_in  & ~Empty_out;
           
    //Addreses (Gray counters) logic:
    GrayCounter GrayCounter_pWr
       (.GrayCount_out(pNextWordToWrite),
       
        .Enable_in(NextWriteAddressEn),
        .Clear_in(Clear_in),
        
        .Clk(WClk)
       );
       
    GrayCounter GrayCounter_pRd
       (.GrayCount_out(pNextWordToRead),
        .Enable_in(NextReadAddressEn),
        .Clear_in(Clear_in),
        .Clk(RClk)
       );
     

    //'EqualAddresses' logic:
    assign EqualAddresses = (pNextWordToWrite == pNextWordToRead);

    //'Quadrant selectors' logic:
    assign Set_Status = (pNextWordToWrite[ADDRESS_WIDTH-2] ~^ pNextWordToRead[ADDRESS_WIDTH-1]) &
                         (pNextWordToWrite[ADDRESS_WIDTH-1] ^  pNextWordToRead[ADDRESS_WIDTH-2]);
                            
    assign Rst_Status = (pNextWordToWrite[ADDRESS_WIDTH-2] ^  pNextWordToRead[ADDRESS_WIDTH-1]) &
                         (pNextWordToWrite[ADDRESS_WIDTH-1] ~^ pNextWordToRead[ADDRESS_WIDTH-2]);
                         
    //'Status' latch logic:
    always @ (Set_Status, Rst_Status, Clear_in) //D Latch w/ Asynchronous Clear & Preset.
        if (Rst_Status | Clear_in)
            Status = 0;  //Going 'Empty'.
        else if (Set_Status)
            Status = 1;  //Going 'Full'.
            
    //'Full_out' logic for the writing port:
    assign PresetFull = Status & EqualAddresses;  //'Full' Fifo.
    
    always @ (posedge WClk, posedge PresetFull) begin//D Flip-Flop w/ Asynchronous Preset.
    // always @ (posedge WClk) begin//D Flip-Flop w/ Asynchronous Preset.    
		if(Clear_in) begin
			Full_out <= 0;
		end
		else begin
			if (PresetFull)
				Full_out <= 1;
			else
				Full_out <= 0;
		end
    end       
    //'Empty_out' logic for the reading port:
    assign PresetEmpty = ~Status & EqualAddresses;  //'Empty' Fifo.
    
    always @ (posedge RClk, posedge PresetEmpty) begin //D Flip-Flop w/ Asynchronous Preset.
	// always @ (posedge RClk) begin //D Flip-Flop w/ Asynchronous Preset.
        if(Clear_in)begin
			Empty_out <= 1;
		end
		else begin
			if (PresetEmpty)
				Empty_out <= 1;
			else
				Empty_out <= 0;
		end
	
	end
            
endmodule


//==========================================
// Function : Code Gray counter.
// Coder    : Alex Claros F.
// Date     : 15/May/2005.
//=======================================

module GrayCounter
   #(parameter   COUNTER_WIDTH = 4)
   
    (output reg  [COUNTER_WIDTH-1:0]    GrayCount_out,  //'Gray' code count output.
    
     input wire                         Enable_in,  //Count enable.
     input wire                         Clear_in,   //Count reset.
    
     input wire                         Clk);

    /////////Internal connections & variables///////
    reg    [COUNTER_WIDTH-1:0]         BinaryCount;

    /////////Code///////////////////////
    
    always @ (posedge Clk)
        if (Clear_in) begin
            BinaryCount   <= {COUNTER_WIDTH{1'b 0}} + 1;  //Gray count begins @ '1' with
            GrayCount_out <= {COUNTER_WIDTH{1'b 0}};      // first 'Enable_in'.
        end
        else if (Enable_in) begin
            BinaryCount   <= BinaryCount + 1;
            GrayCount_out <= {BinaryCount[COUNTER_WIDTH-1],
                              BinaryCount[COUNTER_WIDTH-2:0] ^ BinaryCount[COUNTER_WIDTH-1:1]};
        end
    
endmodule