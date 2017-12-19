#include <pthread.h>

typedef struct batch {
	int idx;
    void* inputAddr;
    void* outputAddr;
    int inputValid;
    int outputValid;
    //pthread_cond_t inputReady;
    pthread_cond_t outputReady;
    pthread_mutex_t batchNodeLock;
    struct batch* next;
    struct batch* prev;
} batch;

extern pthread_mutex_t batchListLock;
extern pthread_mutex_t freeListLock;
extern pthread_cond_t inputReady;
