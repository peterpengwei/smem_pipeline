#include <zlib.h>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <pthread.h>
#include <math.h>
#include <assert.h>
#include "bwa.h"
#include "bwamem.h"
#include "kvec.h"
#include "utils.h"
#include "kseq.h"
#include "utils.h"
KSEQ_DECLARE(gzFile)
extern unsigned char nst_nt4_table[256];

extern unsigned int *handshake;
extern unsigned long int *SPL_BWT_input;
extern unsigned long int *SPL_BWT_output;
extern unsigned int *read_size;
extern unsigned long int *DSM;

#define MAX_MEM_SIZE	1024
#define KERNEL_BATCH_MAX	1024
unsigned long int **worker_mem;
volatile unsigned char *sw_handshake;
pthread_t *worker_threads;

void *kopen(const char *fn, int *_fd);
int kclose(void *a);
static void *harp_management(void *);

int main_mem(int argc, char *argv[])
{
	printf("Entering main_mem\n");
	mem_opt_t *opt, opt0;

	int fd, fd2, i, c, n, copy_comment = 0;
	gzFile fp, fp2 = 0;
	kseq_t *ks, *ks2 = 0;
	bseq1_t *seqs;
	bwaidx_t *idx;
	char *p, *rg_line = 0;
	void *ko = 0, *ko2 = 0;
	int64_t n_processed = 0;
	mem_pestat_t pes[4], *pes0 = 0;

	memset(pes, 0, 4 * sizeof(mem_pestat_t));
	for (i = 0; i < 4; ++i) pes[i].failed = 1;

	opt = mem_opt_init();
	opt0.a = opt0.b = opt0.o_del = opt0.e_del = opt0.o_ins = opt0.e_ins = opt0.pen_unpaired = -1;
	opt0.pen_clip5 = opt0.pen_clip3 = opt0.zdrop = opt0.T = -1;
	while ((c = getopt(argc, argv, "epaMCSPHk:c:v:s:r:t:b:R:A:B:O:E:U:w:L:d:T:Q:D:m:I:")) >= 0) { // [QA] add -b as an attribute
		if (c == 'k') opt->min_seed_len = atoi(optarg);
		else if (c == 'w') opt->w = atoi(optarg);
		else if (c == 'A') opt->a = atoi(optarg), opt0.a = 1;
		else if (c == 'B') opt->b = atoi(optarg), opt0.b = 1;
		else if (c == 'T') opt->T = atoi(optarg), opt0.T = 1;
		else if (c == 'U') opt->pen_unpaired = atoi(optarg), opt0.pen_unpaired = 1;
		else if (c == 't') opt->n_threads = atoi(optarg), opt->n_threads = opt->n_threads > 1? opt->n_threads : 1;
		else if (c == 'b') opt->batch_size = atoi(optarg), opt->batch_size = opt->batch_size > 1? opt->batch_size : 1; // [QA] assign batch size
		else if (c == 'P') opt->flag |= MEM_F_NOPAIRING;
		else if (c == 'a') opt->flag |= MEM_F_ALL;
		else if (c == 'p') opt->flag |= MEM_F_PE;
		else if (c == 'M') opt->flag |= MEM_F_NO_MULTI;
		else if (c == 'S') opt->flag |= MEM_F_NO_RESCUE;
		else if (c == 'e') opt->flag |= MEM_F_NO_EXACT;
		else if (c == 'c') opt->max_occ = atoi(optarg);
		else if (c == 'd') opt->zdrop = atoi(optarg), opt0.zdrop = 1;
		else if (c == 'v') bwa_verbose = atoi(optarg);
		else if (c == 'r') opt->split_factor = atof(optarg);
		else if (c == 'D') opt->chain_drop_ratio = atof(optarg);
		else if (c == 'm') opt->max_matesw = atoi(optarg);
		else if (c == 's') opt->split_width = atoi(optarg);
		else if (c == 'C') copy_comment = 1;
		else if (c == 'Q') {
			opt->mapQ_coef_len = atoi(optarg);
			opt->mapQ_coef_fac = opt->mapQ_coef_len > 0? log(opt->mapQ_coef_len) : 0;
		} else if (c == 'O') {
			opt0.o_del = opt0.o_ins = 1;
			opt->o_del = opt->o_ins = strtol(optarg, &p, 10);
			if (*p != 0 && ispunct(*p) && isdigit(p[1]))
				opt->o_ins = strtol(p+1, &p, 10);
		} else if (c == 'E') {
			opt0.e_del = opt0.e_ins = 1;
			opt->e_del = opt->e_ins = strtol(optarg, &p, 10);
			if (*p != 0 && ispunct(*p) && isdigit(p[1]))
				opt->e_ins = strtol(p+1, &p, 10);
		} else if (c == 'L') {
			opt0.pen_clip5 = opt0.pen_clip3 = 1;
			opt->pen_clip5 = opt->pen_clip3 = strtol(optarg, &p, 10);
			if (*p != 0 && ispunct(*p) && isdigit(p[1]))
				opt->pen_clip3 = strtol(p+1, &p, 10);
		} else if (c == 'R') {
			if ((rg_line = bwa_set_rg(optarg)) == 0) return 1; // FIXME: memory leak
		} else if (c == 'I') { // specify the insert size distribution
			pes0 = pes;
			pes[1].failed = 0;
			pes[1].avg = strtod(optarg, &p);
			pes[1].std = pes[1].avg * .1;
			if (*p != 0 && ispunct(*p) && isdigit(p[1]))
				pes[1].std = strtod(p+1, &p);
			pes[1].high = (int)(pes[1].avg + 4. * pes[1].std + .499);
			pes[1].low  = (int)(pes[1].avg - 4. * pes[1].std + .499);
			if (pes[1].low < 1) pes[1].low = 1;
			if (*p != 0 && ispunct(*p) && isdigit(p[1]))
				pes[1].high = (int)(strtod(p+1, &p) + .499);
			if (*p != 0 && ispunct(*p) && isdigit(p[1]))
				pes[1].low  = (int)(strtod(p+1, &p) + .499);
			if (bwa_verbose >= 3)
				fprintf(stderr, "[M::%s] mean insert size: %.3f, stddev: %.3f, max: %d, min: %d\n",
						__func__, pes[1].avg, pes[1].std, pes[1].high, pes[1].low);
		}
		else return 1;
	}
	printf("Leaving first while in main_mem\n");
	if (opt->n_threads < 1) opt->n_threads = 1;
	if (optind + 1 >= argc || optind + 3 < argc) {
		fprintf(stderr, "\n");
		fprintf(stderr, "Usage: bwa mem [options] <idxbase> <in1.fq> [in2.fq]\n\n");
		fprintf(stderr, "Algorithm options:\n\n");
		fprintf(stderr, "       -t INT        number of threads [%d]\n", opt->n_threads);
		fprintf(stderr, "       -k INT        minimum seed length [%d]\n", opt->min_seed_len);
		fprintf(stderr, "       -w INT        band width for banded alignment [%d]\n", opt->w);
		fprintf(stderr, "       -d INT        off-diagonal X-dropoff [%d]\n", opt->zdrop);
		fprintf(stderr, "       -r FLOAT      look for internal seeds inside a seed longer than {-k} * FLOAT [%g]\n", opt->split_factor);
//		fprintf(stderr, "       -s INT        look for internal seeds inside a seed with less than INT occ [%d]\n", opt->split_width);
		fprintf(stderr, "       -c INT        skip seeds with more than INT occurrences [%d]\n", opt->max_occ);
		fprintf(stderr, "       -D FLOAT      drop chains shorter than FLOAT fraction of the longest overlapping chain [%.2f]\n", opt->chain_drop_ratio);
		fprintf(stderr, "       -m INT        perform at most INT rounds of mate rescues for each read [%d]\n", opt->max_matesw);
		fprintf(stderr, "       -S            skip mate rescue\n");
		fprintf(stderr, "       -P            skip pairing; mate rescue performed unless -S also in use\n");
		fprintf(stderr, "       -e            discard full-length exact matches\n");
		fprintf(stderr, "       -A INT        score for a sequence match, which scales [-TdBOELU] unless overridden [%d]\n", opt->a);
		fprintf(stderr, "       -B INT        penalty for a mismatch [%d]\n", opt->b);
		fprintf(stderr, "       -O INT[,INT]  gap open penalties for deletions and insertions [%d,%d]\n", opt->o_del, opt->o_ins);
		fprintf(stderr, "       -E INT[,INT]  gap extension penalty; a gap of size k cost '{-O} + {-E}*k' [%d,%d]\n", opt->e_del, opt->e_ins);
		fprintf(stderr, "       -L INT[,INT]  penalty for 5'- and 3'-end clipping [%d,%d]\n", opt->pen_clip5, opt->pen_clip3);
		fprintf(stderr, "       -U INT        penalty for an unpaired read pair [%d]\n", opt->pen_unpaired);
		fprintf(stderr, "\nInput/output options:\n\n");
		fprintf(stderr, "       -p            first query file consists of interleaved paired-end sequences\n");
		fprintf(stderr, "       -R STR        read group header line such as '@RG\\tID:foo\\tSM:bar' [null]\n");
		fprintf(stderr, "\n");
		fprintf(stderr, "       -v INT        verbose level: 1=error, 2=warning, 3=message, 4+=debugging [%d]\n", bwa_verbose);
		fprintf(stderr, "       -T INT        minimum score to output [%d]\n", opt->T);
		fprintf(stderr, "       -a            output all alignments for SE or unpaired PE\n");
		fprintf(stderr, "       -C            append FASTA/FASTQ comment to SAM output\n");
		fprintf(stderr, "       -M            mark shorter split hits as secondary\n\n");
		fprintf(stderr, "       -I FLOAT[,FLOAT[,INT[,INT]]]\n");
		fprintf(stderr, "                     specify the mean, standard deviation (10%% of the mean if absent), max\n");
		fprintf(stderr, "                     (4 sigma from the mean if absent) and min of the insert size distribution.\n");
		fprintf(stderr, "                     FR orientation only. [inferred]\n");
		fprintf(stderr, "\nNote: Please read the man page for detailed description of the command line and options.\n");
		fprintf(stderr, "\n");
		free(opt);
		return 1;
	}

	if (opt0.a == 1) { // matching score is changed
		if (opt0.b != 1) opt->b *= opt->a;
		if (opt0.T != 1) opt->T *= opt->a;
		if (opt0.o_del != 1) opt->o_del *= opt->a;
		if (opt0.e_del != 1) opt->e_del *= opt->a;
		if (opt0.o_ins != 1) opt->o_ins *= opt->a;
		if (opt0.e_ins != 1) opt->e_ins *= opt->a;
		if (opt0.zdrop != 1) opt->zdrop *= opt->a;
		if (opt0.pen_clip5 != 1) opt->pen_clip5 *= opt->a;
		if (opt0.pen_clip3 != 1) opt->pen_clip3 *= opt->a;
		if (opt0.pen_unpaired != 1) opt->pen_unpaired *= opt->a;
	}
	bwa_fill_scmat(opt->a, opt->b, opt->mat);

	// comaniac: [NOTE] Load ref. and cnt before creating any thread
	printf("Load ref. and cnt before creating any thread\n");
	if ((idx = bwa_idx_load(argv[optind], BWA_IDX_ALL)) == 0) {
		fprintf(stderr, "Fail to load reference geno and cnt table\n");
		return 1; // FIXME: memory leak
	}

	ko = kopen(argv[optind + 1], &fd);
	if (ko == 0) {
		if (bwa_verbose >= 1) fprintf(stderr, "[E::%s] fail to open file `%s'.\n", __func__, argv[optind + 1]);
		return 1;
	}
	fp = gzdopen(fd, "r");
	ks = kseq_init(fp);
	if (optind + 2 < argc) {
		if (opt->flag&MEM_F_PE) {
			if (bwa_verbose >= 2)
				fprintf(stderr, "[W::%s] when '-p' is in use, the second query file will be ignored.\n", __func__);
		} else {
			ko2 = kopen(argv[optind + 2], &fd2);
			if (ko2 == 0) {
				if (bwa_verbose >= 1) fprintf(stderr, "[E::%s] fail to open file `%s'.\n", __func__, argv[optind + 2]);
				return 1;
			}
			fp2 = gzdopen(fd2, "r");
			ks2 = kseq_init(fp2);
			opt->flag |= MEM_F_PE;
		}
	}
	bwa_print_sam_hdr(idx->bns, rg_line);

	// comanaic: Create manager thread
	printf("Create manager thread\n");
	pthread_t manager;
	pthread_create(&manager, 0, harp_management, &opt->n_threads);

	// comaniac: Malloc worker shared memory
	worker_mem = (unsigned long int **)malloc(sizeof(unsigned long int *) * opt->n_threads);
	for (i = 0; i < opt->n_threads; ++i)
		worker_mem[i] = (unsigned long int *)malloc(sizeof(unsigned long int) * MAX_MEM_SIZE * KERNEL_BATCH_MAX + 1);

	// comaniac: [NOTE] perform BWA-MEM for reads
	int licheng_count = 0;
	while ((seqs = bseq_read(opt->chunk_size * opt->n_threads, &n, ks, ks2)) != 0) {
		printf("workers perform BWA-MEM for reads...%d\n", licheng_count++);
		int64_t size = 0;
		if ((opt->flag & MEM_F_PE) && (n&1) == 1) {
			if (bwa_verbose >= 2)
				fprintf(stderr, "[W::%s] odd number of reads in the PE mode; last read dropped\n", __func__);
			n = n>>1<<1;
		}
		if (!copy_comment)
			for (i = 0; i < n; ++i) {
				free(seqs[i].comment); seqs[i].comment = 0;
			}
		for (i = 0; i < n; ++i) size += seqs[i].l_seq;
		if (bwa_verbose >= 3)
			fprintf(stderr, "[M::%s] read %d sequences (%ld bp)...\n", __func__, n, (long)size);
		// above are verbose seting up? following is the sequence processing
		/*
		typedef struct {
		bwt_t    *bwt; // FM-index
		bntseq_t *bns; // information on the reference sequences
		uint8_t  *pac; // the actual 2-bit encoded reference sequences with 'N' converted to a random base
		} bwaidx_t;  idx
		*/
		fprintf(stderr, "into mem_process_seq\n");
		mem_process_seqs(opt, idx->bwt, idx->bns, idx->pac, n_processed, n, seqs, pes0);
		fprintf(stderr, "outfrom mem_process_seq\n");
		n_processed += n;
		for (i = 0; i < n; ++i) {
			//err_fputs(seqs[i].sam, stdout);
			free(seqs[i].name); free(seqs[i].comment); free(seqs[i].seq); free(seqs[i].qual); free(seqs[i].sam);
		}
		free(seqs);
	}

	// comaniac: Shutdown manager thread
	sw_handshake[opt->n_threads] = 4;
	for (i = 0; i < opt->n_threads; ++i)
		free(worker_mem[i]);
	free(worker_mem);

	free(opt);
	bwa_idx_destroy(idx);
	kseq_destroy(ks);
	err_gzclose(fp); kclose(ko);
	if (ks2) {
		kseq_destroy(ks2);
		err_gzclose(fp2); kclose(ko2);
	}
	return 0;
}

int main_fastmap(int argc, char *argv[])
{
	int c, i, min_iwidth = 20, min_len = 17, print_seq = 0, split_width = 0;
	kseq_t *seq;
	bwtint_t k;
	gzFile fp;
	smem_i *itr;
	const bwtintv_v *a;
	bwaidx_t *idx;

	while ((c = getopt(argc, argv, "w:l:ps:")) >= 0) {
		switch (c) {
			case 's': split_width = atoi(optarg); break;
			case 'p': print_seq = 1; break;
			case 'w': min_iwidth = atoi(optarg); break;
			case 'l': min_len = atoi(optarg); break;
		    default: return 1;
		}
	}
	if (optind + 1 >= argc) {
		fprintf(stderr, "Usage: bwa fastmap [-p] [-s splitWidth=%d] [-l minLen=%d] [-w maxSaSize=%d] <idxbase> <in.fq>\n", split_width, min_len, min_iwidth);
		return 1;
	}

	fp = xzopen(argv[optind + 1], "r");
	seq = kseq_init(fp);
	if ((idx = bwa_idx_load(argv[optind], BWA_IDX_BWT|BWA_IDX_BNS)) == 0) return 1;
	itr = smem_itr_init(idx->bwt);
	while (kseq_read(seq) >= 0) {
		err_printf("SQ\t%s\t%ld", seq->name.s, seq->seq.l);
		if (print_seq) {
			err_putchar('\t');
			err_puts(seq->seq.s);
		} else err_putchar('\n');
		for (i = 0; i < seq->seq.l; ++i)
			seq->seq.s[i] = nst_nt4_table[(int)seq->seq.s[i]];
		smem_set_query(itr, seq->seq.l, (uint8_t*)seq->seq.s);
		while ((a = smem_next(itr, min_len<<1, split_width)) != 0) {
			for (i = 0; i < a->n; ++i) {
				bwtintv_t *p = &a->a[i];
				if ((uint32_t)p->info - (p->info>>32) < min_len) continue;
				err_printf("EM\t%d\t%d\t%ld", (uint32_t)(p->info>>32), (uint32_t)p->info, (long)p->x[2]);
				if (p->x[2] <= min_iwidth) {
					for (k = 0; k < p->x[2]; ++k) {
						bwtint_t pos;
						int len, is_rev, ref_id;
						len  = (uint32_t)p->info - (p->info>>32);
						pos = bns_depos(idx->bns, bwt_sa(idx->bwt, p->x[0] + k), &is_rev);
						if (is_rev) pos -= len - 1;
						bns_cnt_ambi(idx->bns, pos, len, &ref_id);
						err_printf("\t%s:%c%ld", idx->bns->anns[ref_id].name, "+-"[is_rev], (long)(pos - idx->bns->anns[ref_id].offset) + 1);
					}
				} else err_puts("\t*");
				err_putchar('\n');
			}
		}
		err_puts("//");
	}

	smem_itr_destroy(itr);
	bwa_idx_destroy(idx);
	kseq_destroy(seq);
	err_gzclose(fp);
	return 0;
}

static void *harp_management(void * data) {
	int num_counter = 0;
	int nthreads = *((int *) data);
	double afu_time = 0;
	fprintf(stderr, "Launch HARP management to manage %d threads\n", nthreads);
	sw_handshake = (unsigned char *)calloc(nthreads + 1, sizeof(unsigned char));
	// SW inter-thread handshaking: 
	// 0: Worker preparing
	// 1: Worker input data ready
	// 2: Manager output data ready	
	// 3: Manager rejects the request
	// 4: Main thread shutdown
	printf("Entering HARP Manager\n");
	int tick_tock = 0;
	int polling = 0;
	int i, j;
	printf("Thread numbers: %d\n",nthreads);

	unsigned long int timer;
	unsigned long int run_counter;
	unsigned long int request_counter;
	unsigned long int stall_counter;
	unsigned long int load_counter;
	unsigned long int output_counter;
	unsigned long int idle_counter;

	struct OneCL {                      // Make a cache-line sized structure
		unsigned long int dw[8];       //    for array arithmetic
	};
	struct OneCL *dsm = (struct OneCL *)(DSM);


	while (sw_handshake[nthreads] != 4) {
		for (i = 0; i < nthreads; ++i) {
			//fprintf(stderr, "inside for loop, before if\n");
			if (sw_handshake[i] == 1) {
				// Pop input from worker memory
				//fprintf(stderr, "inside if\n");
				unsigned long int read_num = *worker_mem[i];
				*read_size = read_num;
				//fprintf(stderr, "Pop input from worker memory\n");
				memcpy(SPL_BWT_input, worker_mem[i] + 1, sizeof(unsigned long int) * 32 * read_num);
				//fprintf(stderr, "Pop input done\n");
				#if LOG_LEVEL == 2 
				fprintf(stderr, "[MANAGER] Thread %d input ready with %ld reads\n", i, read_num);
				#endif

				// Execute on FPGA
				if (!tick_tock) {
		  			//*handshake = 1;
		  			*handshake = 1 + 2863311520;
					polling = 1;
				}
				else {
					//*handshake = 4;
					*handshake = 4 + 2863311520;
					polling = 4;
				}
				tick_tock = tick_tock ^ 0x1;

			    	int watch_dog = *handshake & 0x0000000f;
	
				double start_time = realtime();
				double this_time = 0;
				#if LOG_LEVEL == 2
		  			fprintf(stderr, "[MANAGER] BWT_Start with polling tag %d\n", polling);
				#endif
#ifdef USE_SW
				int t;
				for (t = 0; t < 10; ++t) {
					for (j = 0; j < nthreads; ++j) {
						if (j == i) continue;
						if (sw_handshake[j] == 1)
							sw_handshake[j] = 3;
					}
					usleep(1);
				}
#else
			  	while (watch_dog == polling) {
		     			for (j = 0; j < nthreads; ++j) {
						if (j == i) continue;
						if (sw_handshake[j] == 1)
							sw_handshake[j] = 3;
						if (watch_dog != polling) break;
					}
					watch_dog = *handshake  & 0x0000000f ;
				}
#endif
				// Finish execution
		    		#if LOG_LEVEL == 2
    					fprintf(stderr, "[MANAGER] BWT_Done = %f\n", realtime() - start_time);
				#endif
				this_time = realtime() - start_time;
				afu_time += realtime() - start_time;

				timer = dsm[0].dw[6];
				run_counter = dsm[0].dw[5];
				request_counter = dsm[0].dw[4];
				stall_counter = dsm[0].dw[3];
				load_counter = dsm[0].dw[2];
				output_counter = dsm[0].dw[1];
				idle_counter = dsm[0].dw[0];
				
				printf("timer = %lu\n", timer);
				printf("run_counter = %lu\n", run_counter);
				printf("request_counter = %lu\n", request_counter);
				printf("stall_counter = %lu\n", stall_counter);
				printf("load_counter = %lu\n", load_counter);
				printf("output_counter = %lu\n", output_counter);
				printf("idle_counter = %lu\n", idle_counter);
				printf("bandwidth = %lf\n", request_counter * 64.0 / this_time / timer / 200000000/1024 / 1024 / 1024);

    			*handshake = 0;

				// The worker has decided to do on CPU
				if (sw_handshake[i] == 0){
					//fprintf(stderr, "worker uses CPU\n");
					continue;
				}

				// Put output back to worker memory and reset the handshake
#ifdef USE_SW
				*worker_mem[i] = 0;
				#if LOG_LEVEL == 2
				fprintf(stderr, "[MANAGER] Set %p for thread %d as 0\n", worker_mem[i], i);
				#endif
#else
				unsigned long int *SPL_BWT_output_ptr = SPL_BWT_output;
				unsigned long int *worker_ptr = worker_mem[i];
				num_counter += read_num;
				//fprintf(stderr, "total num = %d\n", num_counter);
				//fprintf(stderr, "read_num = %d\n", read_num);
				for (j = 0; j < read_num; ++j) {
					bwtint_t out_num = *(SPL_BWT_output_ptr + 1);

					bwtint_t out_size = 0;
					if (out_num % 2)
						out_size = 8 + out_num * 4 + 4;
					else
						out_size = 8 + out_num * 4;
					assert (out_size < MAX_MEM_SIZE);
					//fprintf(stderr, "put output back to worker memory\n");
					memcpy(worker_ptr, SPL_BWT_output_ptr, out_size * sizeof(unsigned long int));	
					//fprintf(stderr, "put output done\n");
					SPL_BWT_output_ptr += out_size;
					worker_ptr += out_size;
				}
//				fprintf(stderr, "worker_ptr = %llx, SPL_BWT_output_ptr = %llx\n", worker_ptr, SPL_BWT_output_ptr );

#endif
				sw_handshake[i] = 2;
//				while (sw_handshake[i] != 0)
//					usleep(1);
			}
		}
	}

	printf("Shutdown HARP management, total kernel time %fs\n", afu_time);
	pthread_exit(0);
}
