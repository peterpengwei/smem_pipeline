import ccip_if_pkg::*;
module afu_top #(
    parameter NEXT_DFH_BYTE_OFFSET = 0
) (
    input  wire                             clk,
    input  wire                             CLK_200M,
    input  wire                             spl_reset,

    // AFU TX read request
    input  wire                             spl_tx_rd_almostfull,
    output wire                             afu_tx_rd_valid,
    output t_ccip_c0_ReqMemHdr              afu_tx_rd_hdr,

    // AFU TX write request
    input  wire                             spl_tx_wr_almostfull,
    output wire                             afu_tx_wr_valid,
    output t_ccip_c1_ReqMemHdr              afu_tx_wr_hdr,
    output wire [511:0]     afu_tx_data,

    // AFU TX MMIO read response
    output t_if_ccip_c2_Tx                  afu_tx_mmio,

    // AFU RX read response
    input  wire                             spl_rx_rd_valid,
    input  wire                             spl_mmio_rd_valid,
    input  wire                             spl_mmio_wr_valid,
    input  t_ccip_c0_RspMemHdr              spl_rx_rd_hdr,
    input  wire [511:0]     spl_rx_data,

    // AFU RX write response
    input  wire                             spl_rx_wr_valid,
    input  t_ccip_c1_RspMemHdr              spl_rx_wr_hdr
);

	//-------------------------------------------------
	
	wire                             io_rx_rd_valid;
    wire  [511:0]                    io_rx_data; 
	
	wire                             cor_tx_rd_valid;
    wire [57:0]                      cor_tx_rd_addr;
    wire [5:0]                       cor_tx_rd_len;
	
	wire                             cor_tx_wr_valid;
    wire                             cor_tx_dsr_valid;
    wire                             cor_tx_fence_valid;
    wire                             cor_tx_done_valid;        
    wire [57:0]                      cor_tx_wr_addr; 
    wire [5:0]                       cor_tx_wr_len;
    wire [511:0]                     cor_tx_data;
	
	wire                             csr_id_valid;
    wire                             csr_id_done;
    wire  [31:0]                     csr_id_addr;
	
	wire                             csr_ctx_base_valid;
    wire  [57:0]                     csr_ctx_base;
	
	wire            				 core_reset_n;
	wire            				 core_start;
	
	wire [63:0] 					 io_src_ptr;
	wire [63:0] 					 io_dst_ptr;
	wire [63:0] dsm_base_addr;	
	afu_core afu_core(
		.CLK_400M(clk),
		.CLK_200M(CLK_200M),
		.reset_n(core_reset_n),
		
		.core_start_d(core_start),
		.spl_reset(spl_reset),
		
		// TX_RD request, afu_core --> afu_io
		.spl_tx_rd_almostfull(spl_tx_rd_almostfull),
		.cor_tx_rd_valid(cor_tx_rd_valid),
		.cor_tx_rd_addr(cor_tx_rd_addr),
		.cor_tx_rd_len(cor_tx_rd_len),  // in CL, 0-64, 1-1, 2-2, ...63-63
		
		
		// TX_WR request, afu_core --> afu_io
		.spl_tx_wr_almostfull(spl_tx_wr_almostfull),    
		.cor_tx_wr_valid(cor_tx_wr_valid),
		.cor_tx_dsr_valid(cor_tx_dsr_valid),
		.cor_tx_fence_valid(cor_tx_fence_valid),
		.cor_tx_done_valid(cor_tx_done_valid),
		.cor_tx_wr_addr(cor_tx_wr_addr), 
		.cor_tx_wr_len(cor_tx_wr_len), 
		.cor_tx_data(cor_tx_data),
				 
		// RX_RD response, afu_io --> afu_core
		.io_rx_rd_valid(io_rx_rd_valid),
		.io_rx_data(io_rx_data),    
					 
		// afu_csr --> afu_core, afu_id
		.csr_id_valid(csr_id_valid),
		.csr_id_done(csr_id_done),    
		.csr_id_addr(csr_id_addr),
			
		 // afu_csr --> afu_core, afu_ctx   
		.csr_ctx_base_valid(csr_ctx_base_valid),
		.csr_ctx_base(csr_ctx_base),
		
		.dsm_base_addr(dsm_base_addr),
		.io_src_ptr(io_src_ptr),
		.io_dst_ptr(io_dst_ptr)
	);
	
	 afu_io #(
        .NEXT_DFH_BYTE_OFFSET(NEXT_DFH_BYTE_OFFSET)
    ) afu_io (
	
		.clk(clk),
		.spl_reset(spl_reset),

		// AFU TX read request
		.spl_tx_rd_almostfull(spl_tx_rd_almostfull), //[Not needed here]
		.afu_tx_rd_valid(afu_tx_rd_valid),
		.afu_tx_rd_hdr(afu_tx_rd_hdr),

		// AFU TX write request
		.spl_tx_wr_almostfull(spl_tx_wr_almostfull), //[Not needed here]
		.afu_tx_wr_valid(afu_tx_wr_valid),
		.afu_tx_wr_hdr(afu_tx_wr_hdr),
		.afu_tx_data(afu_tx_data),

		// AFU TX MMIO read response
		.afu_tx_mmio(afu_tx_mmio),

		// AFU RX read response, MMIO request
		.spl_rx_rd_valid(spl_rx_rd_valid),
		.spl_mmio_rd_valid(spl_mmio_rd_valid),
		.spl_mmio_wr_valid(spl_mmio_wr_valid),
		.spl_rx_rd_hdr(spl_rx_rd_hdr),
		.spl_rx_data(spl_rx_data),

		// AFU RX write response
		.spl_rx_wr_valid(spl_rx_wr_valid),
		.spl_rx_wr_hdr(spl_rx_wr_hdr),
		   
		//============================================================
		
		
		// RX_RD response, afu_io --> afu_core
		.io_rx_rd_valid(io_rx_rd_valid),
		.io_rx_data(io_rx_data),    
			
		// TX_RD request(), afu_core --> afu_io
		.cor_tx_rd_valid(cor_tx_rd_valid),
		.cor_tx_rd_addr(cor_tx_rd_addr),
		.cor_tx_rd_len(cor_tx_rd_len),
		
		// TX_WR request, afu_core --> afu_io
		.cor_tx_wr_valid(cor_tx_wr_valid),
		.cor_tx_dsr_valid(cor_tx_dsr_valid),
		.cor_tx_fence_valid(cor_tx_fence_valid),
		.cor_tx_done_valid(cor_tx_done_valid),        
		.cor_tx_wr_addr(cor_tx_wr_addr), 
		.cor_tx_wr_len(cor_tx_wr_len),
		.cor_tx_data(cor_tx_data),     

		// afu_io --> afu_core
		.dsm_base_addr(dsm_base_addr),
		.io_src_ptr(io_src_ptr),
		.io_dst_ptr(io_dst_ptr),
		
		// afu_csr-->afu_core, afu_id
		.csr_id_valid(csr_id_valid),
		.csr_id_done(csr_id_done),
		.csr_id_addr(csr_id_addr),
		
		// afu_csr-->afu_core, afu_ctx_base
		.csr_ctx_base_valid(csr_ctx_base_valid),
		.csr_ctx_base(csr_ctx_base),
		
		.core_reset_n(core_reset_n),
		.core_start(core_start)
	);
	
endmodule
