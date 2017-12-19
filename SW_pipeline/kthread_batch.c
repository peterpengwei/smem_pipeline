#include <pthread.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/syscall.h>

extern pthread_t *worker_threads;

struct kt_for_batch_t;
//int bv=0;
//int threadnum = 0;
typedef struct {
	struct kt_for_batch_t *t;
	int i;
} ktf_worker_batch_t;

typedef struct kt_for_batch_t {
	int n_threads, n, batch_size;
	ktf_worker_batch_t *w;
	void (*func)(void*,int,int,int);
	void *data;
} kt_for_batch_t;

static inline int steal_work(kt_for_batch_t *t)
{
	int i, k, min = 0x7fffffff, min_i = -1;
	for (i = 0; i < t->n_threads; ++i)
		if (min > t->w[i].i) min = t->w[i].i, min_i = i;
	k = __sync_fetch_and_add(&t->w[min_i].i, t->n_threads*t->batch_size);
	return k >= t->n? -1 : k;
}

static void *ktf_worker_batch(void *data)
{
	int tid = (int)syscall(SYS_gettid);
	ktf_worker_batch_t *w = (ktf_worker_batch_t*)data;
	int i, batch_size;
	for (;;) {
		//fprintf(stderr, "thread[%d],before __sync_fetch_and_add, w->i=%d\n", tid, w->i);
		i = __sync_fetch_and_add(&w->i, w->t->n_threads*w->t->batch_size);// w->i + #of threads*batch_size
		//fprintf(stderr, "thread[%d],after __sync_fetch_and_add, w->i=%d, i=%d, w->t->n = %d \n", tid, w->i,i, w->t->n);
		if (i >= w->t->n) break;
		batch_size = w->t->n-i > w->t->batch_size? w->t->batch_size : w->t->n-i;
		//fprintf(stderr, "thread[%d],batch_size = %d\n", tid, batch_size);
		w->t->func(w->t->data, i, batch_size, w - w->t->w); //die here!!! >32 died immediately the first created thread will die
	}
	while ((i = steal_work(w->t)) >= 0) {
		
		batch_size = w->t->n-i > w->t->batch_size? w->t->batch_size : w->t->n-i;
		
		w->t->func(w->t->data, i, batch_size, tid);
	}

	pthread_exit(0);
}

void kt_for_batch(int n_threads, void (*func)(void*,int,int,int), void *data, int n, int batch_size)
{
	int i;
	kt_for_batch_t t;
	pthread_t *tid;
	t.func = func, t.data = data, t.n_threads = n_threads, t.n = n, t.batch_size = batch_size;
	t.w = (ktf_worker_batch_t*)alloca(n_threads * sizeof(ktf_worker_batch_t));
	tid = (pthread_t*)alloca(n_threads * sizeof(pthread_t));
	worker_threads = tid;
	for (i = 0; i < n_threads; ++i)
		t.w[i].t = &t, t.w[i].i = i*batch_size;
	for (i = 0; i < n_threads; ++i) pthread_create(&tid[i], 0, ktf_worker_batch, &t.w[i]);
	fprintf(stderr, "into kt_for_batch, finish creating threads!!!\n");
	for (i = 0; i < n_threads; ++i) 
		if(pthread_join(tid[i],0)!=0) 
			fprintf(stderr, "error joining %d thread", tid[i]);
	fprintf(stderr, "into kt_for_batch, finish joining threads!!!\n");
}
