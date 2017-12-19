// BWA-MEM-HARP2 By Licheng
//****************************************************************************
#include <aalsdk/AALTypes.h>
#include <aalsdk/Runtime.h>
#include <aalsdk/AALLoggerExtern.h>

#include <aalsdk/service/IALIAFU.h>
#include "IMPF.h"

#include <string.h>

#include <math.h>

//****************************************************************************
// UN-COMMENT appropriate #define in order to enable either Hardware or ASE.
//    DEFAULT is to use Software Simulation.
//****************************************************************************
//#define  HWAFU
#define  ASEAFU

using namespace std;
using namespace AAL;

// Convenience macros for printing messages and errors.
#ifdef MSG
# undef MSG
#endif // MSG
#define MSG(x) std::cout << __AAL_SHORT_FILE__ << ':' << __LINE__ << ':' << __AAL_FUNC__ << "() : " << x << std::endl
#ifdef ERR
# undef ERR
#endif // ERR
#define ERR(x) std::cerr << __AAL_SHORT_FILE__ << ':' << __LINE__ << ':' << __AAL_FUNC__ << "() **Error : " << x << std::endl

// Print/don't print the event ID's entered in the event handlers.
#if 1
# define EVENT_CASE(x) case x : MSG(#x);
#else
# define EVENT_CASE(x) case x :
#endif

#ifndef CL
# define CL(x)                     ((x) * 64)
#endif // CL
#ifndef LOG2_CL
# define LOG2_CL                   6
#endif // LOG2_CL
#ifndef MB
# define MB(x)                     ((x) * 1024 * 1024)
#endif // MB

#define CSR_SRC_ADDR            0x0120
#define CSR_DST_ADDR            0x0128
#define CSR_CTL                 0x0148

#define CSR_AFU_DSM_BASEL        0x0110
#define CSR_AFU_DSM_BASEH        0x0114

#define LB_BUFFER_SIZE MB(3080)
#define BWT_ref    MB(3072)
#define CNT_table  MB(1)
#define BWT_input  MB(1)
#define BWT_output MB(1)

unsigned int *SPL_BWT_ref;
unsigned int *SPL_CNT_table;
unsigned int *read_size;
unsigned int *handshake;
unsigned long int *SPL_BWT_input;
unsigned long int *SPL_BWT_output;
unsigned long int *SPL_input_base;
unsigned long int *SPL_output_base;
unsigned long int *DSM;
unsigned long int *source_data;

// define bwa_top //
extern "C"
{
	int top_main(int argc, char *argv[]);
}


/// @addtogroup MMULApp
/// @{


/// @brief   Since this is a simple application, our App class implements both the IRuntimeClient and IServiceClient
///           interfaces.  Since some of the methods will be redundant for a single object, they will be ignored.
///
class MMULApp: public CAASBase, public IRuntimeClient, public IServiceClient
{
public:

   MMULApp();
   ~MMULApp();

   btInt run(int argc, char *argv[]);    ///< Return 0 if success

   // <begin IServiceClient interface>
   void serviceAllocated(IBase *pServiceBase,
                         TransactionID const &rTranID);

   void serviceAllocateFailed(const IEvent &rEvent);

   void serviceReleased(const AAL::TransactionID&);
   void serviceReleaseRequest(IBase *pServiceBase, const IEvent &rEvent);
   void serviceReleaseFailed(const AAL::IEvent&);

   void serviceEvent(const IEvent &rEvent);
   // <end IServiceClient interface>

   // <begin IRuntimeClient interface>
   void runtimeCreateOrGetProxyFailed(IEvent const &rEvent){};    // Not Used

   void runtimeStarted(IRuntime            *pRuntime,
                       const NamedValueSet &rConfigParms);

   void runtimeStopped(IRuntime *pRuntime);

   void runtimeStartFailed(const IEvent &rEvent);

   void runtimeStopFailed(const IEvent &rEvent);

   void runtimeAllocateServiceFailed( IEvent const &rEvent);

   void runtimeAllocateServiceSucceeded(IBase               *pClient,
                                        TransactionID const &rTranID);

   void runtimeEvent(const IEvent &rEvent);

   btBool isOK()  {return m_bIsOK;}

   // <end IRuntimeClient interface>
protected:
   Runtime        m_Runtime;                ///< AAL Runtime
   IBase         *m_pALIAFU_AALService;     ///< The generic AAL Service interface for the AFU.
   IALIBuffer    *m_pALIBufferService;      ///< Pointer to Buffer Service
   IALIMMIO      *m_pALIMMIOService;        ///< Pointer to MMIO Service
   IALIReset     *m_pALIResetService;       ///< Pointer to AFU Reset Service
   CSemaphore     m_Sem;                    ///< For synchronizing with the AAL runtime.
   btInt          m_Result;                 ///< Returned result value; 0 if success
   TransactionID  m_ALIAFUTranID;           ///< TransactionID used for service allocation

   // VTP service-related information
   IBase         *m_pVTP_AALService;        ///< The generic AAL Service interface for the VTP.
   IMPFVTP       *m_pVTPService;            ///< Pointer to VTP buffer service
   btCSROffset    m_VTPDFHOffset;           ///< VTP DFH offset
   TransactionID  m_VTPTranID;              ///< TransactionID used for service allocation

   // Workspace info
   btVirtAddr     m_DSMVirt;        ///< DSM workspace virtual address.
   btWSSize       m_DSMSize;        ///< DSM workspace size in bytes.
   btVirtAddr     m_InputVirt;     ///< Input workspace virtual address0.
   btWSSize       m_InputSize;      ///< Input workspace size in bytes.
   btVirtAddr     m_OutputVirt;     ///< Output workspace virtual address.
   btWSSize       m_OutputSize;     ///< Output workspace size in bytes.
};

///////////////////////////////////////////////////////////////////////////////
///
///  Implementation
///
///////////////////////////////////////////////////////////////////////////////

/// @brief   Constructor registers this objects client interfaces and starts
///          the AAL Runtime. The member m_bisOK is used to indicate an error.
///
MMULApp::MMULApp() :
   m_Runtime(this),
   m_pALIAFU_AALService(NULL),
   m_pALIBufferService(NULL),
   m_pALIMMIOService(NULL),
   m_pALIResetService(NULL),
   m_pVTP_AALService(NULL),
   m_pVTPService(NULL),
   m_VTPDFHOffset(-1),
   m_Result(0),
   //m_DSMVirt(NULL),
  // m_DSMSize(0),
   m_InputVirt(NULL),
   //m_InputVirt1(NULL),
   m_InputSize(0),
   m_OutputVirt(NULL),
   m_OutputSize(0),
   m_ALIAFUTranID(),
   m_VTPTranID()
{
   // Register our Client side interfaces so that the Service can acquire them.
   //   SetInterface() is inherited from CAASBase
   SetInterface(iidServiceClient, dynamic_cast<IServiceClient *>(this));
   SetInterface(iidRuntimeClient, dynamic_cast<IRuntimeClient *>(this));

   // Initialize our internal semaphore
   m_Sem.Create(0, 1);

   // Start the AAL Runtime, setting any startup options via a NamedValueSet

   // Using Hardware Services requires the Remote Resource Manager Broker Service
   //  Note that this could also be accomplished by setting the environment variable
   //   AALRUNTIME_CONFIG_BROKER_SERVICE to librrmbroker
   NamedValueSet configArgs;
   NamedValueSet configRecord;

#if defined( HWAFU )
   // Specify that the remote resource manager is to be used.
   configRecord.Add(AALRUNTIME_CONFIG_BROKER_SERVICE, "librrmbroker");
   configArgs.Add(AALRUNTIME_CONFIG_RECORD, &configRecord);
#endif

   // Start the Runtime and wait for the callback by sitting on the semaphore.
   //   the runtimeStarted() or runtimeStartFailed() callbacks should set m_bIsOK appropriately.
   if(!m_Runtime.start(configArgs)){
      m_bIsOK = false;
      return;
   }
   m_Sem.Wait();
   m_bIsOK = true;
}

/// @brief   Destructor
///
MMULApp::~MMULApp()
{
   m_Sem.Destroy();
}

/// @brief   run() is called from main performs the following:
///             - Allocate the appropriate ALI Service depending
///               on whether a hardware, ASE or software implementation is desired.
///             - Allocates the necessary buffers to be used by the NLB AFU algorithm
///             - Executes the NLB algorithm
///             - Cleans up.
///
btInt MMULApp::run(int argc, char *argv[])
{
   cout <<"======================="<<endl;
   cout <<"=  Hello Licheng BWA  ="<<endl;
   cout <<"======================="<<endl;

   // Request the Servcie we are interested in.

   // NOTE: This example is bypassing the Resource Manager's configuration record lookup
   //  mechanism.  Since the Resource Manager Implementation is a sample, it is subject to change.
   //  This example does illustrate the utility of having different implementations of a service all
   //  readily available and bound at run-time.
   NamedValueSet Manifest;
   NamedValueSet ConfigRecord;
   NamedValueSet featureFilter;
   btcString sGUID = MPF_VTP_BBB_GUID;

#if defined( HWAFU )                /* Use FPGA hardware */
   // Service Library to use
   ConfigRecord.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_SERVICE_NAME, "libALI");

   // the AFUID to be passed to the Resource Manager. It will be used to locate the appropriate device.
   ConfigRecord.Add(keyRegAFU_ID,"04242017-DEAD-BEEF-DEAD-BEEF01234567");


   // indicate that this service needs to allocate an AIAService, too to talk to the HW
   ConfigRecord.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_AIA_NAME, "libaia");

#elif defined ( ASEAFU )         /* Use ASE based RTL simulation */
   Manifest.Add(keyRegHandle, 20);
   Manifest.Add(ALIAFU_NVS_KEY_TARGET, ali_afu_ase);

   ConfigRecord.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_SERVICE_NAME, "libASEALIAFU");
   ConfigRecord.Add(AAL_FACTORY_CREATE_SOFTWARE_SERVICE,true);

#else                            /* default is Software Simulator */
#if 0 // NOT CURRRENTLY SUPPORTED
   ConfigRecord.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_SERVICE_NAME, "libSWSimALIAFU");
   ConfigRecord.Add(AAL_FACTORY_CREATE_SOFTWARE_SERVICE,true);
#endif
   return -1;
#endif

   // Add the Config Record to the Manifest describing what we want to allocate
   Manifest.Add(AAL_FACTORY_CREATE_CONFIGRECORD_INCLUDED, &ConfigRecord);

   // in future, everything could be figured out by just giving the service name
   Manifest.Add(AAL_FACTORY_CREATE_SERVICENAME, "ALI");

   MSG("Allocating ALIAFU Service");

   // Allocate the Service and wait for it to complete by sitting on the
   //   semaphore. The serviceAllocated() callback will be called if successful.
   //   If allocation fails the serviceAllocateFailed() should set m_bIsOK appropriately.
   //   (Refer to the serviceAllocated() callback to see how the Service's interfaces
   //    are collected.)
   //  Note that we are passing a custom transaction ID (created during app
   //   construction) to be able in serviceAllocated() to identify which
   //   service was allocated. This is only necessary if you are allocating more
   //   than one service from a single AAL service client.
   m_Runtime.allocService(dynamic_cast<IBase *>(this), Manifest, m_ALIAFUTranID);
   m_Sem.Wait();
   if(!m_bIsOK){
      ERR("ALIAFU allocation failed\n");
      goto done_0;
   }

   // Ask the ALI service for the VTP device feature header (DFH)
   // featureFilter.Add(ALI_GETFEATURE_ID_KEY, static_cast<ALI_GETFEATURE_ID_DATATYPE>(25));
   //featureFilter.Add(ALI_GETFEATURE_TYPE_KEY, static_cast<ALI_GETFEATURE_TYPE_DATATYPE>(2));
   // featureFilter.Add(ALI_GETFEATURE_GUID_KEY, static_cast<ALI_GETFEATURE_GUID_DATATYPE>(sGUID));
   // if (true != m_pALIMMIOService->mmioGetFeatureOffset(&m_VTPDFHOffset, featureFilter)) {
   //    ERR("No VTP feature\n");
   //    m_bIsOK = false;
   //    m_Result = -1;
   //    goto done_1;
   // }

   // Reuse Manifest and Configrecord for VTP service
   Manifest.Empty();
   ConfigRecord.Empty();

   // Allocate VTP service
   // Service Library to use
   ConfigRecord.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_SERVICE_NAME, "libMPF");
   ConfigRecord.Add(AAL_FACTORY_CREATE_SOFTWARE_SERVICE,true);

   // Add the Config Record to the Manifest describing what we want to allocate
   Manifest.Add(AAL_FACTORY_CREATE_CONFIGRECORD_INCLUDED, &ConfigRecord);

   // the VTPService will reuse the already established interfaces presented by
   // the ALIAFU service
   Manifest.Add(ALIAFU_IBASE_KEY, static_cast<ALIAFU_IBASE_DATATYPE>(m_pALIAFU_AALService));

   // MPFs feature ID, used to find correct features in DFH list
   Manifest.Add(MPF_FEATURE_ID_KEY, static_cast<MPF_FEATURE_ID_DATATYPE>(1));

   // in future, everything could be figured out by just giving the service name
   Manifest.Add(AAL_FACTORY_CREATE_SERVICENAME, "VTP");

   MSG("Allocating VTP Service");

   m_Runtime.allocService(dynamic_cast<IBase *>(this), Manifest, m_VTPTranID);
   m_Sem.Wait();
   if(!m_bIsOK){
      ERR("VTP Service allocation failed\n");
      goto done_0;
   }
	MSG("VTP Service allocated");
   // Now that we have the Service and have saved the IALIBuffer interface pointer
   //  we can now Allocate the 3 Workspaces used by the NLB algorithm. The buffer allocate
   //  function is synchronous so no need to wait on the semaphore

   // Device Status Memory (DSM) is a structure defined by the NLB implementation.

   // User Virtual address of the pointer is returned directly in the function
   // Remember, we're using VTP, so no need to convert to physical addresses
   if( ali_errnumOK != m_pVTPService->bufferAllocate(MB(1), &m_DSMVirt)){
      m_bIsOK = false;
      m_Result = -1;
      goto done_2;
   }

   // Save the size
   m_DSMSize = MB(1);

   // Repeat for the Input and Output Buffers
   m_InputSize = LB_BUFFER_SIZE;
   if( ali_errnumOK != m_pVTPService->bufferAllocate(m_InputSize, &m_InputVirt)){
      m_bIsOK = false;
      m_Sem.Post(1);
      m_Result = -1;
      goto done_3;
   }

   m_OutputSize = BWT_output;
   if( ali_errnumOK !=  m_pVTPService->bufferAllocate(m_OutputSize, &m_OutputVirt)){
      m_bIsOK = false;
      m_Sem.Post(1);
      m_Result = -1;
      goto done_4;
   }

   //=============================
   // Now we have the NLB Service
   //   now we can use it
   //=============================
   MSG("Running Test");

   if(true == m_bIsOK){
      MSG("m_pDSM == 0x" << std::hex << (btUnsigned64bitInt)m_DSMVirt);
      MSG("m_pInput == 0x" << std::hex << (btUnsigned64bitInt)m_InputVirt);
      MSG("m_pOutput == 0x" << std::hex << (btUnsigned64bitInt)m_OutputVirt);

	  struct OneCL {                      // Make a cache-line sized structure
		  btUnsigned32bitInt dw[16];       //    for array arithmetic
	  };
	  struct OneCL      *pSourceCL = reinterpret_cast<struct OneCL *>(m_InputVirt);
	  struct OneCL      *pDestCL = reinterpret_cast<struct OneCL *>(m_OutputVirt);

	  //[divide the input buffer into different segments]
	  SPL_BWT_ref = (unsigned int *)(m_InputVirt);
	  SPL_CNT_table = (unsigned int *)(m_InputVirt);
	  handshake = (unsigned int *)(m_InputVirt);
	  read_size = (unsigned int *)(m_InputVirt);
	  SPL_BWT_input = (unsigned long int *)(m_InputVirt);
	  SPL_input_base = (unsigned long int *)(m_InputVirt);

	  SPL_BWT_output = (unsigned long int *)(m_OutputVirt);
	  SPL_output_base = (unsigned long int *)(m_OutputVirt);

	  DSM = (unsigned long int*)m_DSMVirt;
	  // [Licheng] note that for different types of pointers, the action of "+" is not the same.

	  SPL_CNT_table += BWT_ref / sizeof(unsigned int);
	  handshake += ((BWT_ref + CNT_table) / sizeof(unsigned int)) - 1;
	  read_size += ((BWT_ref + CNT_table) / sizeof(unsigned int)) - 2;
	  SPL_BWT_input += (BWT_ref + CNT_table) / sizeof(unsigned long int);
	  SPL_input_base += (BWT_ref + CNT_table) / sizeof(unsigned long int);

	  //SPL_BWT_output += (BWT_ref + CNT_table + BWT_input) / sizeof(unsigned long int);
	  //SPL_output_base += (BWT_ref + CNT_table + BWT_input) / sizeof(unsigned long int);

	  // Clear the DSM
          ::memset(m_DSMVirt, 0, m_DSMSize);
	  ::memset(m_InputVirt, 0, m_InputSize);
	  ::memset(m_OutputVirt, 0, m_OutputSize);


      // Initiate AFU Reset
      m_pALIResetService->afuReset();

      // AFU Reset clear VTP, too, so reinitialize hardware
      m_pVTPService->vtpReset();


      // Assert AFU reset
      m_pALIMMIOService->mmioWrite32(CSR_CTL, 0);

      //De-Assert AFU reset
      m_pALIMMIOService->mmioWrite32(CSR_CTL, 1);

      // If ASE, give it some time to catch up
      #if defined ( ASEAFU )
		SleepSec(5);
      #endif /* ASE AFU */


      // Initiate DSM Reset
      // Set DSM base, high then low
      m_pALIMMIOService->mmioWrite64(CSR_AFU_DSM_BASEL, (btUnsigned64bitInt)m_DSMVirt / CL(1));

      // Set input workspace address
      m_pALIMMIOService->mmioWrite64(CSR_SRC_ADDR, (btUnsigned64bitInt)(m_InputVirt) / CL(1));

      // Set output workspace address
      m_pALIMMIOService->mmioWrite64(CSR_DST_ADDR, (btUnsigned64bitInt)(m_OutputVirt) / CL(1));

      // Start the test
      m_pALIMMIOService->mmioWrite32(CSR_CTL, 3);

      MSG("Start Running Test");
	  // The AFU is running
	  ////////////////////////////////////////////////////////////////////////////

	  int top_val;
	  MSG("Before entering top_main()");
	  top_val = top_main(argc, argv);

	  ////////////////////////////////////////////////////////////////////////////


      // Stop the device
      m_pALIMMIOService->mmioWrite32(CSR_CTL, 7);

   }
   MSG("Done Running Test");

   // Clean-up and return
done_4:
   m_pVTPService->bufferFree(m_OutputVirt);
done_3:
   m_pVTPService->bufferFree(m_InputVirt);
done_2:

done_1:
   // Freed all three so now Release() the Service through the Services IAALService::Release() method
   (dynamic_ptr<IAALService>(iidService, m_pALIAFU_AALService))->Release(TransactionID());
   m_Sem.Wait();

done_0:
   m_Runtime.stop();
   m_Sem.Wait();

   return m_Result;
}

//=================
//  IServiceClient
//=================

// <begin IServiceClient interface>
void MMULApp::serviceAllocated(IBase *pServiceBase,
                                      TransactionID const &rTranID)
{
   // This application will allocate two different services (HWALIAFU and
   //  VTPService). We can tell them apart here by looking at the TransactionID.
   if (rTranID ==  m_ALIAFUTranID) {

      // Save the IBase for the Service. Through it we can get any other
      //  interface implemented by the Service
      m_pALIAFU_AALService = pServiceBase;
      ASSERT(NULL != m_pALIAFU_AALService);
      if ( NULL == m_pALIAFU_AALService ) {
         m_bIsOK = false;
         return;
      }

      // Documentation says HWALIAFU Service publishes
      //    IALIBuffer as subclass interface. Used in Buffer Allocation and Free
      m_pALIBufferService = dynamic_ptr<IALIBuffer>(iidALI_BUFF_Service, pServiceBase);
      ASSERT(NULL != m_pALIBufferService);
      if ( NULL == m_pALIBufferService ) {
         m_bIsOK = false;
         return;
      }

      // Documentation says HWALIAFU Service publishes
      //    IALIMMIO as subclass interface. Used to set/get MMIO Region
      m_pALIMMIOService = dynamic_ptr<IALIMMIO>(iidALI_MMIO_Service, pServiceBase);
      ASSERT(NULL != m_pALIMMIOService);
      if ( NULL == m_pALIMMIOService ) {
         m_bIsOK = false;
         return;
      }

      // Documentation says HWALIAFU Service publishes
      //    IALIReset as subclass interface. Used for resetting the AFU
      m_pALIResetService = dynamic_ptr<IALIReset>(iidALI_RSET_Service, pServiceBase);
      ASSERT(NULL != m_pALIResetService);
      if ( NULL == m_pALIResetService ) {
         m_bIsOK = false;
         return;
      }

      MSG("ALI Service Allocated");
   }
   else if (rTranID == m_VTPTranID) {

      // Save the IBase for the VTP Service.
       m_pVTP_AALService = pServiceBase;
       ASSERT(NULL != m_pVTP_AALService);
       if ( NULL == m_pVTP_AALService ) {
          m_bIsOK = false;
          return;
       }

       // Documentation says VTP Service publishes
       //    IVTP as subclass interface. Used for allocating shared
       //    buffers that support virtual addresses from AFU
       m_pVTPService = dynamic_ptr<IMPFVTP>(iidMPFVTPService, pServiceBase);
       ASSERT(NULL != m_pVTPService);
       if ( NULL == m_pVTPService ) {
          m_bIsOK = false;
          return;
       }

       MSG("VTP Service Allocated");
   }
   else
   {
      ERR("Unknown transaction ID encountered on serviceAllocated().");
      m_bIsOK = false;
      return;
   }

   m_Sem.Post(1);
}

void MMULApp::serviceAllocateFailed(const IEvent &rEvent)
{
   ERR("Failed to allocate Service");
    PrintExceptionDescription(rEvent);
   ++m_Result;                     // Remember the error
   m_bIsOK = false;

   m_Sem.Post(1);
}

 void MMULApp::serviceReleased(TransactionID const &rTranID)
{
    MSG("Service Released");
   // Unblock Main()
   m_Sem.Post(1);
}

 void MMULApp::serviceReleaseRequest(IBase *pServiceBase, const IEvent &rEvent)
 {
    MSG("Service unexpected requested back");
    if(NULL != m_pALIAFU_AALService){
       IAALService *pIAALService = dynamic_ptr<IAALService>(iidService, m_pALIAFU_AALService);
       ASSERT(pIAALService);
       pIAALService->Release(TransactionID());
    }
 }


 void MMULApp::serviceReleaseFailed(const IEvent        &rEvent)
 {
    ERR("Failed to release a Service");
    PrintExceptionDescription(rEvent);
    m_bIsOK = false;
    m_Sem.Post(1);
 }


 void MMULApp::serviceEvent(const IEvent &rEvent)
{
   ERR("unexpected event 0x" << hex << rEvent.SubClassID());
   // The state machine may or may not stop here. It depends upon what happened.
   // A fatal error implies no more messages and so none of the other Post()
   //    will wake up.
   // OTOH, a notification message will simply print and continue.
}
// <end IServiceClient interface>


 //=================
 //  IRuntimeClient
 //=================

  // <begin IRuntimeClient interface>
 // Because this simple example has one object implementing both IRuntieCLient and IServiceClient
 //   some of these interfaces are redundant. We use the IServiceClient in such cases and ignore
 //   the RuntimeClient equivalent e.g.,. runtimeAllocateServiceSucceeded()

 void MMULApp::runtimeStarted( IRuntime            *pRuntime,
                                      const NamedValueSet &rConfigParms)
 {
    m_bIsOK = true;
    m_Sem.Post(1);
 }

 void MMULApp::runtimeStopped(IRuntime *pRuntime)
  {
     MSG("Runtime stopped");
     m_bIsOK = false;
     m_Sem.Post(1);
  }

 void MMULApp::runtimeStartFailed(const IEvent &rEvent)
 {
    ERR("Runtime start failed");
    PrintExceptionDescription(rEvent);
 }

 void MMULApp::runtimeStopFailed(const IEvent &rEvent)
 {
     MSG("Runtime stop failed");
     m_bIsOK = false;
     m_Sem.Post(1);
 }

 void MMULApp::runtimeAllocateServiceFailed( IEvent const &rEvent)
 {
    ERR("Runtime AllocateService failed");
    PrintExceptionDescription(rEvent);
 }

 void MMULApp::runtimeAllocateServiceSucceeded(IBase *pClient,
                                                     TransactionID const &rTranID)
 {
     MSG("Runtime Allocate Service Succeeded");
 }

 void MMULApp::runtimeEvent(const IEvent &rEvent)
 {
     MSG("Generic message handler (runtime)");
 }
 // <begin IRuntimeClient interface>

/// @} group MMULApp


//=============================================================================
// Name: main
// Description: Entry point to the application
// Inputs: none
// Outputs: none
// Comments: Main initializes the system. The rest of the example is implemented
//           in the object theApp.
//=============================================================================
int main(int argc, char *argv[])
{

   MMULApp theApp;
   if(!theApp.isOK()){
      ERR("Runtime Failed to Start");
      exit(1);
   }
   btInt Result = theApp.run(argc, argv);

   MSG("Done");

   if (0 == Result) {
      MSG("======= SUCCESS =======");
   } else {
      MSG("!!!!!!! FAILURE !!!!!!!");
   }

   return Result;
}

