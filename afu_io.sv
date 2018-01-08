import ccip_if_pkg::*;
import ccip_feature_list_pkg::*;

module afu_io#(
  parameter NEXT_DFH_BYTE_OFFSET = 0
)
(
/*     input  wire                             clk,
    input  wire                             reset_n,
    input  wire                             spl_enable,
    input  wire                             spl_reset,
    
    // AFU TX read request
    output reg                              afu_tx_rd_valid,
    output reg [98:0]                       afu_tx_rd_hdr,
    
    // AFU TX write request
    output reg                              afu_tx_wr_valid,
    output reg                              afu_tx_intr_valid,
    output reg [98:0]                       afu_tx_wr_hdr,
    output reg [511:0]                      afu_tx_data,
    
    // AFU RX read response
    input  wire                             spl_rx_rd_valid,
    input  wire                             spl_rx_wr_valid0,
    input  wire                             spl_rx_cfg_valid,
    input  wire                             spl_rx_intr_valid0,
    input  wire                             spl_rx_umsg_valid,
    input  wire [17:0]     spl_rx_hdr0,
    input  wire [511:0]                     spl_rx_data,
    
    // AFU RX write response
    input  wire                             spl_rx_wr_valid1,
    input  wire                             spl_rx_intr_valid1,
    input  wire [17:0]     spl_rx_hdr1, */
	
	//===========================================================
	
	input  wire                             clk,
	input  wire                             spl_reset,

	// AFU TX read request
	input  wire                             spl_tx_rd_almostfull, //[Not needed here]
	output reg                              afu_tx_rd_valid,
	output t_ccip_c0_ReqMemHdr              afu_tx_rd_hdr,

	// AFU TX write request
	input  wire                             spl_tx_wr_almostfull, //[Not needed here]
	output reg                              afu_tx_wr_valid,
	output t_ccip_c1_ReqMemHdr              afu_tx_wr_hdr,
	output reg [511:0]      afu_tx_data,

	// AFU TX MMIO read response
	output t_if_ccip_c2_Tx                  afu_tx_mmio,

	// AFU RX read response, MMIO request
	input  wire                             spl_rx_rd_valid,
	input  wire                             spl_mmio_rd_valid,
	input  wire                             spl_mmio_wr_valid,
	input  t_ccip_c0_RspMemHdr              spl_rx_rd_hdr,
	input  wire [511:0]     spl_rx_data,

	// AFU RX write response
	input  wire                             spl_rx_wr_valid,
	input  t_ccip_c1_RspMemHdr              spl_rx_wr_hdr,
       
	//============================================================
	
    
    // RX_RD response, afu_io --> afu_core
    output  reg                             io_rx_rd_valid,
    output  reg  [511:0]                    io_rx_data,    
        
    // TX_RD request, afu_core --> afu_io
    input  wire                             cor_tx_rd_valid,
    input  wire [57:0]                      cor_tx_rd_addr,
    input  wire [5:0]                       cor_tx_rd_len,
    
    // TX_WR request, afu_core --> afu_io
    input  wire                             cor_tx_wr_valid,
    input  wire                             cor_tx_dsr_valid,
    input  wire                             cor_tx_fence_valid,
    input  wire                             cor_tx_done_valid,        
    input  wire [57:0]                      cor_tx_wr_addr, 
    input  wire [5:0]                       cor_tx_wr_len,
    input  wire [511:0]                     cor_tx_data,     

	// afu_io --> afu_core
	output reg [63:0]  						io_src_ptr,
	output reg [63:0] 						io_dst_ptr,
	output reg [63:0]  						io_hand_ptr,
	output reg [63:0] 						io_input_base,
 	output reg [63:0]  						dsm_base_addr,
	
	// afu_csr-->afu_core, afu_id
    output reg                              csr_id_valid,
    input  wire                             csr_id_done,
    output reg  [31:0]                      csr_id_addr,
	
	// afu_csr-->afu_core, afu_ctx_base
    output reg                              csr_ctx_base_valid,
    output reg  [57:0]                      csr_ctx_base,
	
	output  reg            core_reset_n,
	output  reg            core_start
);

	reg  [5:0]                      tx_wr_tag;
    reg  [5:0]                      tx_rd_tag;           
     
    reg                             tx_wr_block;
    reg  [5:0]                      tx_wr_block_cnt;
	
	
	//-------------------------------------------------------            
    // TX_WR, drive afu_tx_wr port
    //-------------------------------------------------------	
	always @(posedge clk) begin
		if (spl_reset) begin
		
			afu_tx_data <= 0;
			afu_tx_wr_hdr <= 0;
			afu_tx_wr_valid <= 1'b0;
			
			tx_wr_block <= 1'b0;
			tx_wr_tag <= 0;
		end
		
		else begin
			
			if (cor_tx_wr_valid) begin
			
				afu_tx_data <= cor_tx_data;
				afu_tx_wr_valid <= 1'b1;	
				
				case ({cor_tx_fence_valid, cor_tx_done_valid})
                    
                    2'b10 : begin      // fence
                        /* afu_tx_wr_hdr <= {6'b0, 26'b0, 6'b0 ,5'b0, `CCI_REQ_WR_FENCE ,6'b0, 32'b0, 14'b0}; */    

						//afu_tx_wr_hdr.vc_sel   <= eVC_VA;
						afu_tx_wr_hdr.vc_sel   <= eVC_VL0;
						afu_tx_wr_hdr.req_type <= eREQ_WRFENCE;
						afu_tx_wr_hdr.address  <= 42'h0;
						afu_tx_wr_hdr.mdata    <= 16'h0;
						afu_tx_wr_hdr.sop      <= 1'b0;        
						afu_tx_wr_hdr.cl_len   <= eCL_LEN_1;   
                    end
                    
                    2'b01 : begin      // done
                        /* afu_tx_wr_hdr <= {cor_tx_wr_len, cor_tx_wr_addr[57:32], 1'b1, 5'b0 ,5'b0, `CCI_REQ_WR ,6'b0, cor_tx_wr_addr[31:0], 8'h3, tx_wr_tag};*/ 
						
						tx_wr_tag <= tx_wr_tag + 1;
						
						//afu_tx_wr_hdr.vc_sel   <= eVC_VA;
						afu_tx_wr_hdr.vc_sel   <= eVC_VL0;
						afu_tx_wr_hdr.req_type <= eREQ_WRLINE_M;
						afu_tx_wr_hdr.address  <= cor_tx_wr_addr[41:0];
						afu_tx_wr_hdr.mdata    <= {9'b0, tx_wr_tag};
						afu_tx_wr_hdr.sop      <= 1'b1;        // TODO: multi-CL
						afu_tx_wr_hdr.cl_len   <= eCL_LEN_1;   // TODO: multi-CL
						
                    end                    

                    default : begin     // mem_wr
                        //afu_tx_wr_hdr <= {cor_tx_wr_len, cor_tx_wr_addr[57:32], 1'b1, 5'b0 ,5'b0, `CCI_REQ_WR ,6'b0, cor_tx_wr_addr[31:0], 8'h3, tx_wr_tag};
                        
						//afu_tx_wr_hdr.vc_sel   <= eVC_VA;
						afu_tx_wr_hdr.vc_sel   <= eVC_VL0;
						afu_tx_wr_hdr.req_type <= eREQ_WRLINE_M;
						afu_tx_wr_hdr.address  <= cor_tx_wr_addr[41:0];
						afu_tx_wr_hdr.mdata    <= {9'b0, tx_wr_tag};
						afu_tx_wr_hdr.sop      <= 1'b1;        // TODO: multi-CL
						afu_tx_wr_hdr.cl_len   <= eCL_LEN_1;   // TODO: multi-CL

						
                        if (~tx_wr_block) begin                            
                            if (cor_tx_wr_len > 6'h1) begin     // block write
                                tx_wr_block <= 1'b1;
                                tx_wr_block_cnt <= cor_tx_wr_len - 1'b1;
                            end
                            else begin
                                tx_wr_tag <= tx_wr_tag + 1'b1;
                            end
                        end
                        else begin
                            if (tx_wr_block_cnt > 6'h1) begin
                                tx_wr_block_cnt <= tx_wr_block_cnt - 1'b1;
                            end
                            else begin
                                tx_wr_block <= 1'b0;
                                tx_wr_tag <= tx_wr_tag + 1'b1;
                            end
                        end
                    end
                endcase				
			end
			
			else begin
				afu_tx_wr_valid <= 1'b0;
				afu_tx_data <= afu_tx_data;
				afu_tx_wr_hdr <= afu_tx_wr_hdr;
				
			end			
		end
	end
	
	
	//-------------------------------------------------------            
    // TX_RD, drive afu_tx_rd port
    //-------------------------------------------------------
    always @(posedge clk) begin
        if (spl_reset) begin
            afu_tx_rd_valid <= 1'b0;
            tx_rd_tag <= 6'b0;
			afu_tx_rd_hdr <= 10;
        end

        else begin
            afu_tx_rd_valid <= 1'b0;
            
            if (cor_tx_rd_valid) begin
                afu_tx_rd_valid <= 1'b1;
                //afu_tx_rd_hdr <= {cor_tx_rd_len, cor_tx_rd_addr[57:32], 6'b0 ,5'b0, `CCI_REQ_RD ,6'b0, cor_tx_rd_addr[31:0], 8'h2, tx_rd_tag};
                tx_rd_tag <= tx_rd_tag + 1'b1;
				
				//afu_tx_rd_hdr.vc_sel   <= eVC_VA;
				afu_tx_rd_hdr.vc_sel   <= eVC_VL0;
				afu_tx_rd_hdr.req_type <= eREQ_RDLINE_S;
				afu_tx_rd_hdr.address  <= cor_tx_rd_addr[41:0];
				afu_tx_rd_hdr.mdata    <= {9'b0, tx_rd_tag};
				afu_tx_rd_hdr.cl_len   <= eCL_LEN_1;
		
            end
        end
    end 
	
	//-------------------------------------------------------            
    // RX, forward data to afu_core
    //-------------------------------------------------------
    always @(posedge clk) begin
        io_rx_rd_valid <= spl_rx_rd_valid;
        io_rx_data <= spl_rx_data;        
    end
	
	

	
	
	
	
	//============================================================================================
	
	
	
	
	
	
	
	
	
	
	
	
	//-------------------------------------------------------
	// CSR Address Map (byte address)
	//-------------------------------------------------------

	localparam  CSR_AFH_DFH_BASE  = 16'h000;     // RO - Start for the DFH info for this AFU
	localparam  CSR_AFH_ID_L      = 16'h008;     // RO - Lower 64 bits of the AFU ID
	localparam  CSR_AFH_ID_H      = 16'h010;     // RO - Upper 64 bits of the AFU ID
	localparam  CSR_DFH_RSVD0     = 16'h018;     // RO - Offset to next AFU
	localparam  CSR_DFH_RSVD1     = 16'h020;     // RO - Reserved space for DFH managment

	

	//-------------------------------------------------------

	t_ccip_c0_ReqMmioHdr mmio_req_hdr;
	t_ccip_mmioData      mmio_req_data;

	// RX.c0 interleaves memory rd responses and MMIO rd/wr requests
	always @(*) begin
		mmio_req_hdr = t_ccip_c0_ReqMmioHdr'(spl_rx_rd_hdr);
		mmio_req_data = spl_rx_data[CCIP_MMIODATA_WIDTH-1:0];
	end

	// AFU discovery - SW reads DFH and AFU ID
	always @(posedge clk) begin
	
		if (spl_mmio_rd_valid) begin
			case ({mmio_req_hdr.address[13:0], 2'b0})  // use byte address
			
				CSR_AFH_DFH_BASE: begin
					t_ccip_dfh afu_dfh;
					afu_dfh = ccip_dfh_defaultDFH();
					afu_dfh.f_type = eFTYP_AFU;
					afu_dfh.nextFeature = NEXT_DFH_BYTE_OFFSET;

					afu_tx_mmio.data        <= afu_dfh;
					afu_tx_mmio.mmioRdValid <= 1'b1;
					afu_tx_mmio.hdr         <= mmio_req_hdr.tid;
				end
				
				CSR_AFH_ID_L   : begin
					afu_tx_mmio.data        <= 64'hdead_beef_0123_4567;
					afu_tx_mmio.mmioRdValid <= 1'b1;
					afu_tx_mmio.hdr         <= mmio_req_hdr.tid;
				end
				
				CSR_AFH_ID_H   : begin
					afu_tx_mmio.data        <= 64'h0424_2017_dead_beef;
					afu_tx_mmio.mmioRdValid <= 1'b1;
					afu_tx_mmio.hdr         <= mmio_req_hdr.tid;
				end
				
				CSR_DFH_RSVD0  : begin
					afu_tx_mmio.data        <= 64'h0;
					afu_tx_mmio.mmioRdValid <= 1'b1;
					afu_tx_mmio.hdr         <= mmio_req_hdr.tid;
				end
				
				CSR_DFH_RSVD1  : begin
					afu_tx_mmio.data        <= 64'h0;
					afu_tx_mmio.mmioRdValid <= 1'b1;
					afu_tx_mmio.hdr         <= mmio_req_hdr.tid;
				end
				
				default: begin
					afu_tx_mmio.data        <= 64'h0;
					afu_tx_mmio.mmioRdValid <= 1'b0;
					afu_tx_mmio.hdr         <= 0;
				end
			endcase
		end 
		
		else begin
			afu_tx_mmio.mmioRdValid <= 1'b0;
			afu_tx_mmio.hdr         <= 0;
			afu_tx_mmio.data        <= 64'h0;
		end
	end
	
	//------------------------------------------------------
	
	localparam  CSR_AFU_DSM_BASEL = 16'h110;     // 32b RW - Lower 32-bits of AFU DSM base address. The lower 6-bbits are 4x00 since the address is cache aligned.
	localparam  CSR_AFU_DSM_BASEH = 16'h114;     // 32b RW - Upper 32-bits of AFU DSM base address.

/* 	localparam  CSR_SRC_ADDR0     = 16'h120;     // 64b RW - Matrix 0 src address
	localparam  CSR_SRC_ADDR1     = 16'h128;     // 64b RW - Matrix 1 src address
	localparam  CSR_DST_ADDR      = 16'h130;     // 64b RW - Output address
	localparam  CSR_MATRIX_SIZE   = 16'h138;     // 32b RW
	localparam  CSR_BATCH_SIZE    = 16'h140;     // 32b RW */
	
	localparam CSR_SRC_ADDR = 16'h120; //64b RW - Source buffer address
	localparam CSR_DST_ADDR = 16'h128; //64b RW - Destination buffer address
	localparam CSR_HAND_PTR = 16'h130; //64b RW - Source buffer address
	localparam CSR_INPUT_BASE = 16'h138; //64b RW - Destination buffer address

	localparam  CSR_CTL           = 16'h148;     // 32b RW   Control CSR to start n stop the test
	reg  [31:0]  csr_ctl;
	
	//-------------------------------------------------------
	// DSM Address Map (byte address)
	//-------------------------------------------------------
	//localparam  DSM_STATUS        = 32'h40;      // 512b RO  Ttest status and error info
	
	//reg  [41:0]  dsm_stat_address;
	
	//-------------------------------------------------------
	reg [63:0]  io_src_ptr_d;
	reg [63:0]  io_dst_ptr_d;
	reg [63:0]  hand_ptr_d;
	reg [63:0]  input_base_d;
	// SW writes CSR
	always @(posedge clk) begin
		if (spl_reset) begin
			dsm_base_addr           <= 64'b0;
			csr_ctl                 <= 32'b0;
			
			//-------------------
			csr_id_valid <= 1'b0;
			csr_ctx_base_valid <= 1'b0;
			//-------------------
		end
		else begin
			//-------------------
			//if (csr_id_done) csr_id_valid <= 1'b0; //[commenting this line results in csr_id_valid forever being 1]
			//-------------------
			
			if (spl_mmio_wr_valid ) begin
				case ({mmio_req_hdr.address[13:0], 2'b0})  // use byte address
					CSR_AFU_DSM_BASEL : begin
						dsm_base_addr <= mmio_req_data; // DSM pointer

					end
	
					CSR_SRC_ADDR : begin
						io_src_ptr_d <= mmio_req_data;	// source pointer
					end
					
					CSR_DST_ADDR : begin
						io_dst_ptr_d <= mmio_req_data;	// destination pointer
					end
					
					CSR_HAND_PTR: begin
						hand_ptr_d <= mmio_req_data;					
					end
					
					CSR_INPUT_BASE : begin
						input_base_d <= mmio_req_data;
						
						//--------------
						csr_ctx_base_valid <= 1'b1;
						csr_id_valid <= 1'b1;
						//--------------
					end
					
					CSR_CTL      : begin
						csr_ctl    <= mmio_req_data[31:0];
						io_src_ptr <= io_src_ptr_d;
						io_dst_ptr <= io_dst_ptr_d;
						io_hand_ptr <= hand_ptr_d;
						io_input_base <= input_base_d;
					end
					default:;
				endcase
			end
		end
	end
	
	//---------------------------------------------------------------------

	// afu states
	always @(posedge clk) begin
		if (spl_reset) begin
			core_start        <= 0;
			core_reset_n      <= 0;
		end 

		else begin
			core_reset_n      <= csr_ctl[0];
			core_start        <= csr_ctl[1]; 
		end
	end
	
	
	
endmodule
	
	
	
	
	
	
	
	
	
	
  
