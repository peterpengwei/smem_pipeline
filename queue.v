//The read itself should also be stored in a centered structure.
//previously 8 bits represent a nucleobase => too wasteful 
//=> convert to 4-bit data

//if every time pull 1000 reads into the chip
//read itself 4*101
//curr_queue 256*101;
//mem_queue 256*101; 
// ** why Bug made it 256*128?
// ** besides, I highly doubt one entry needs 256 bits.


//Other elements (current nucleobase, status registers, etc.) 
//will all run in the pipeline

//==========================


module Queue(
	input Clk_32UI,
	input reset_n,
	input stall,
	
	input DRAM_get,
	input [31:0] cnt_a0,cnt_a1,cnt_a2,cnt_a3,
	input [63:0] cnt_b0,cnt_b1,cnt_b2,cnt_b3,
	input [31:0] cntl_a0,cntl_a1,cntl_a2,cntl_a3,
	input [63:0] cntl_b0,cntl_b1,cntl_b2,cntl_b3,
	
	//Pipeline -> Queue
	input [5:0] status,
	input [6:0] ptr_curr, // record the status of curr and mem queue
	input [9:0] read_num,
	input [63:0] ik_x0, ik_x1, ik_x2, ik_info,
	input [6:0] forward_i,
	input [6:0] min_intv,

	
	//Queue -> Pipeline
	output reg [5:0] status_out,
	output reg [6:0] ptr_curr_out, // record the status of curr and mem queue
	output reg [9:0] read_num_out,
	output reg [63:0] ik_x0_out, ik_x1_out, ik_x2_out, ik_info_out,
	output reg [6:0] forward_i_out,
	output reg [6:0] min_intv_out,
	output reg [7:0] query_out,
	
	output reg [31:0] cnt_a0_out,cnt_a1_out,cnt_a2_out,cnt_a3_out,
	output reg [63:0] cnt_b0_out,cnt_b1_out,cnt_b2_out,cnt_b3_out,
	output reg [31:0] cntl_a0_out,cntl_a1_out,cntl_a2_out,cntl_a3_out,
	output reg [63:0] cntl_b0_out,cntl_b1_out,cntl_b2_out,cntl_b3_out,

	//fetch new read at the end of queue
	output new_read,
	input new_read_valid,
	input load_done,
	
	input [9:0] new_read_num, //should be prepared before hand. every time new_read is set, next_read_num should be updated.
	input [63:0] new_ik_x0, new_ik_x1, new_ik_x2, new_ik_info,
	input [6:0] new_forward_i,
	
	//fetch new query at the start of queue
	output [7:0] query_position_2RAM,
	output [9:0] query_read_num_2RAM,
	output [5:0] query_status_2RAM,
	input [7:0] new_read_query_2Queue
);
	//6+7+7+10+256+7+7+8 = 308
	parameter F_WIDTH = 308;
	parameter B_WIDTH = 0;
	parameter DEPTH = 256;
	
	parameter F_init = 0; // F_init will disable the forward pipeline
	parameter F_run = 1;
	parameter F_break = 2;
	parameter B_init = 3;
	parameter B_run = 4;
	parameter DONE = 6'b111111;
	
	reg [9:0] read_ptr_f;
	reg [9:0] write_ptr_f;
	
	reg [5:0] status_L0;
	reg [6:0] ptr_curr_L0; // record the status of curr and mem queue
	reg [9:0] read_num_L0;
	reg [63:0] ik_x0_L0, ik_x1_L0, ik_x2_L0, ik_info_L0;
	reg [6:0] forward_i_L0;
	reg [6:0] min_intv_L0;
	
	reg [5:0] status_L1;
	reg [6:0] ptr_curr_L1; // record the status of curr and mem queue
	reg [9:0] read_num_L1;
	reg [63:0] ik_x0_L1, ik_x1_L1, ik_x2_L1, ik_info_L1;
	reg [6:0] forward_i_L1;
	reg [6:0] min_intv_L1;
	
	reg [5:0] status_L2;
	reg [6:0] ptr_curr_L2; // record the status of curr and mem queue
	reg [9:0] read_num_L2;
	reg [63:0] ik_x0_L2, ik_x1_L2, ik_x2_L2, ik_info_L2;
	reg [6:0] forward_i_L2;
	reg [6:0] min_intv_L2;
	
	reg [F_WIDTH-1:0] f_data;
	reg [5:0] status_L3;
	
	// 3 stage pipe to wait for the delay of retrieving query
	//------------------------------------------------
	
	assign query_position_2RAM = forward_i+1;
	assign query_read_num_2RAM = read_num;
	assign query_status_2RAM = status;
	
	always@(posedge Clk_32UI) begin
		status_L0 <= status;
		ptr_curr_L0 <= ptr_curr; // record the status of curr and mem queue
		read_num_L0 <= read_num;
		ik_x0_L0 <= ik_x0;
		ik_x1_L0 <= ik_x1;
		ik_x2_L0 <= ik_x2;
		ik_info_L0 <= ik_info;
		forward_i_L0 <= forward_i;
		min_intv_L0 <= min_intv;

	end
	
	always@(posedge Clk_32UI) begin
		status_L1 <= status_L0;
		ptr_curr_L1 <= ptr_curr_L0; // record the status of curr and mem queue
		read_num_L1 <= read_num_L0;
		ik_x0_L1 <= ik_x0_L0;
		ik_x1_L1 <= ik_x1_L0;
		ik_x2_L1 <= ik_x2_L0;
		ik_info_L1 <= ik_info_L0;
		forward_i_L1 <= forward_i_L0;
		min_intv_L1 <= min_intv_L0;
	end
	
	always@(posedge Clk_32UI) begin
		status_L2 <= status_L1;
		ptr_curr_L2 <= ptr_curr_L1; // record the status of curr and mem queue
		read_num_L2 <= read_num_L1;
		ik_x0_L2 <= ik_x0_L1;
		ik_x1_L2 <= ik_x1_L1;
		ik_x2_L2 <= ik_x2_L1;
		ik_info_L2 <= ik_info_L1;
		forward_i_L2 <= forward_i_L1;
		min_intv_L2 <= min_intv_L1;
	end
	
	
	always@(posedge Clk_32UI) begin
		//received query fetch responses from RAM
		f_data <= {ptr_curr_L2, read_num_L2, ik_x0_L2, ik_x1_L2, ik_x2_L2, ik_info_L2, forward_i_L2, min_intv_L2, new_read_query_2Queue, status_L2};
		status_L3 <= status_L2;
	end
	
	//------------------------------------------------
	
	reg [F_WIDTH + B_WIDTH - 1 :0] RAM_forward[DEPTH-1:0];
	reg [F_WIDTH + B_WIDTH - 1 :0] output_data;

	//circular queue for reads
	always@(posedge Clk_32UI) begin
		if(!reset_n) begin
			write_ptr_f <= 0;
		end
		else if(!stall) begin	
			if((status_L3 == F_init) ||(status_L3 == F_run) || (status_L3 == F_break)) begin 
				RAM_forward[write_ptr_f] <= f_data;
				write_ptr_f <= write_ptr_f + 1;
			end
			
			//else if (status_L3 == B_)
			
			
			
		end
	end
	
	//circular queue for memory responses.
	reg [767:0] RAM_memory[31:0];
	reg [5:0] read_ptr_m;
	reg [5:0] write_ptr_m;
	wire memory_valid = (write_ptr_m != read_ptr_m);
	
	always@(posedge Clk_32UI) begin
		if(!reset_n) begin
			write_ptr_m <= 0;
		end
		else begin
			if(DRAM_get) begin
				RAM_memory[write_ptr_m] <= {cnt_a0,cnt_a1,cnt_a2,cnt_a3,cnt_b0,cnt_b1,cnt_b2,cnt_b3, cntl_a0,cntl_a1,cntl_a2,cntl_a3,cntl_b0,cntl_b1,cntl_b2,cntl_b3};
				write_ptr_m <= write_ptr_m + 1;
			end
		end
	end
	
	assign new_read = (load_done) & new_read_valid & (!memory_valid) & (!stall);
	
	always@(posedge Clk_32UI) begin
		if (!reset_n) begin
			read_ptr_f <= 0;
			read_ptr_m <= 0;
			status_out <= DONE;
		end
		else if (!stall) begin
			if (memory_valid) begin // get memory responses, output old read
				if(read_ptr_f != write_ptr_f) begin
					{ptr_curr_out, read_num_out, ik_x0_out, ik_x1_out, ik_x2_out, ik_info_out, forward_i_out,min_intv_out, query_out, status_out} <= RAM_forward[read_ptr_f];
					{cnt_a0_out,cnt_a1_out,cnt_a2_out,cnt_a3_out,cnt_b0_out,cnt_b1_out,cnt_b2_out,cnt_b3_out, cntl_a0_out,cntl_a1_out,cntl_a2_out,cntl_a3_out,cntl_b0_out,cntl_b1_out,cntl_b2_out,cntl_b3_out} <= RAM_memory[read_ptr_m];
					read_ptr_f <= read_ptr_f + 1;
					read_ptr_m <= read_ptr_m + 1;

				end
				else begin //impossible to happen
					
					//-------------------
                    status_out <= DONE;
                    ptr_curr_out <= 7'b111_1111;
                    read_num_out <= 10'b11_1111_1111; 
                    ik_x0_out <= 64'h1111_1111_1111_1111; 
                    ik_x1_out <= 64'h1111_1111_1111_1111;  
                    ik_x2_out <= 64'h1111_1111_1111_1111;  
                    ik_info_out <= 64'h1111_1111_1111_1111; 
                    forward_i_out <= 7'b111_1111;
                    min_intv_out <= 7'b111_1111; 
                    query_out <= 8'b1111_1111; 
                    //-------------------
					
					cnt_a0_out <= 32'h1111_1111;
					cnt_a1_out <= 32'h1111_1111;
					cnt_a2_out <= 32'h1111_1111;
					cnt_a3_out <= 32'h1111_1111;
					cnt_b0_out <= 64'h1111_1111_1111_1111;
					cnt_b1_out <= 64'h1111_1111_1111_1111;
					cnt_b2_out <= 64'h1111_1111_1111_1111;
					cnt_b3_out <= 64'h1111_1111_1111_1111;
					cntl_a0_out <= 32'h1111_1111;
					cntl_a1_out <= 32'h1111_1111;
					cntl_a2_out <= 32'h1111_1111;
					cntl_a3_out <= 32'h1111_1111;
					cntl_b0_out <= 64'h1111_1111_1111_1111;
					cntl_b1_out <= 64'h1111_1111_1111_1111;
					cntl_b2_out <= 64'h1111_1111_1111_1111;
					cntl_b3_out <= 64'h1111_1111_1111_1111;
                    
					read_ptr_f <= read_ptr_f;
				end
			end
			
			
			else if (new_read_valid) begin // no memory response, fetch new read
				// new_read <= 1;
				//-------------------
                status_out <= F_init;
                ptr_curr_out <= 0;
                read_num_out <= new_read_num; //from RAM
                ik_x0_out <= new_ik_x0; //from RAM
                ik_x1_out <= new_ik_x1; //from RAM
                ik_x2_out <= new_ik_x2; //from RAM
                ik_info_out <= new_ik_info; //from RAM
                forward_i_out <= new_forward_i; // from RAM
                min_intv_out <= 1; 
                query_out <= 0; // !!!!the first round doesn't need query
                
                //-------------------
				
				cnt_a0_out <= 32'h1111_1111;
				cnt_a1_out <= 32'h1111_1111;
				cnt_a2_out <= 32'h1111_1111;
				cnt_a3_out <= 32'h1111_1111;
				cnt_b0_out <= 64'h1111_1111_1111_1111;
				cnt_b1_out <= 64'h1111_1111_1111_1111;
				cnt_b2_out <= 64'h1111_1111_1111_1111;
				cnt_b3_out <= 64'h1111_1111_1111_1111;
				cntl_a0_out <= 32'h1111_1111;
				cntl_a1_out <= 32'h1111_1111;
				cntl_a2_out <= 32'h1111_1111;
				cntl_a3_out <= 32'h1111_1111;
				cntl_b0_out <= 64'h1111_1111_1111_1111;
				cntl_b1_out <= 64'h1111_1111_1111_1111;
				cntl_b2_out <= 64'h1111_1111_1111_1111;
				cntl_b3_out <= 64'h1111_1111_1111_1111;
				
				read_ptr_f <= read_ptr_f;
			end
			else begin // no memory responses and no more reads
				// new_read <= 0;
				//-------------------
                status_out <= DONE;
				ptr_curr_out <= 7'b111_1111;
				read_num_out <= 10'b11_1111_1111; 
				ik_x0_out <= 64'h1111_1111_1111_1111; 
				ik_x1_out <= 64'h1111_1111_1111_1111;  
				ik_x2_out <= 64'h1111_1111_1111_1111;  
				ik_info_out <= 64'h1111_1111_1111_1111; 
				forward_i_out <= 7'b111_1111;
				min_intv_out <= 7'b111_1111; 
				query_out <= 8'b1111_1111; 
                
                //-------------------
				
				cnt_a0_out <= 32'h1111_1111;
				cnt_a1_out <= 32'h1111_1111;
				cnt_a2_out <= 32'h1111_1111;
				cnt_a3_out <= 32'h1111_1111;
				cnt_b0_out <= 64'h1111_1111_1111_1111;
				cnt_b1_out <= 64'h1111_1111_1111_1111;
				cnt_b2_out <= 64'h1111_1111_1111_1111;
				cnt_b3_out <= 64'h1111_1111_1111_1111;
				cntl_a0_out <= 32'h1111_1111;
				cntl_a1_out <= 32'h1111_1111;
				cntl_a2_out <= 32'h1111_1111;
				cntl_a3_out <= 32'h1111_1111;
				cntl_b0_out <= 64'h1111_1111_1111_1111;
				cntl_b1_out <= 64'h1111_1111_1111_1111;
				cntl_b2_out <= 64'h1111_1111_1111_1111;
				cntl_b3_out <= 64'h1111_1111_1111_1111;
				
				read_ptr_f <= read_ptr_f;
			
			
			end
		end
	end	

endmodule
