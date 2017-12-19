#ifndef QA_TOP_H
#define QA_TOP_H

#ifndef CL
# define CL(x)                     ((x) * 64)
#endif // CL
#ifndef LOG2_CL
# define LOG2_CL                   6
#endif // LOG2_CL
#ifndef MB
# define MB(x)                     ((x) * 1024 * 1024)
#endif // MB

#define CACHELINE_ALIGNED_ADDR(p)  ((p) >> LOG2_CL)

#define BWA_NUM_BATCHES            4
#define BWA_INPUT_BUFFER_SIZE      CL(4096)     // the size of TBB
#define BWA_OUTPUT_BUFFER_SIZE     CL(256)      // the size of RBB

#define BWA_DSM_SIZE             MB(4)

#define CSR_CIPUCTL                0x280

#define CSR_AFU_DSM_BASEL          0x1a00
#define CSR_AFU_DSM_BASEH          0x1a04
#define CSR_SRC_ADDR               0x1a20
#define CSR_DST_ADDR               0x1a24
#define CSR_REQ_PEARRAY            0x1a28
#define CSR_CTL                    0x1a2c
#define CSR_CFG                    0x1a34

#define CSR_OFFSET(x)              ((x) / sizeof(bt32bitCSR))

#define DSM_STATUS_PEARRAY		   0x40
#define DSM_STATUS_TEST_ERROR      0x44
#define DSM_STATUS_MODE_ERROR_0    0x60

#define DSM_STATUS_ERROR_REGS      8

#endif
