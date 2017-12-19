/* The MIT License

   Copyright (c) 2008 Genome Research Ltd (GRL).

   Permission is hereby granted, free of charge, to any person obtaining
   a copy of this software and associated documentation files (the
   "Software"), to deal in the Software without restriction, including
   without limitation the rights to use, copy, modify, merge, publish,
   distribute, sublicense, and/or sell copies of the Software, and to
   permit persons to whom the Software is furnished to do so, subject to
   the following conditions:

   The above copyright notice and this permission notice shall be
   included in all copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
   EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
   MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
   NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
   BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
   ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
   CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE.
*/

/* Contact: Heng Li <lh3@sanger.ac.uk> */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <stdint.h>
#include "utils.h"
#include "bwt.h"
#include "kvec.h"
#include "bwamem.h"
#ifdef USE_MALLOC_WRAPPERS
#  include "malloc_wrap.h"
#endif

extern int CCI_RW(unsigned int RW_option, unsigned int RW_CL);
extern volatile unsigned int *pInput;
extern volatile unsigned int *pOutput;

void bwt_gen_cnt_table(bwt_t *bwt)
{
	int i, j;
	for (i = 0; i != 256; ++i) {
		uint32_t x = 0;
		for (j = 0; j != 4; ++j)
			x |= (((i&3) == j) + ((i>>2&3) == j) + ((i>>4&3) == j) + (i>>6 == j)) << (j<<3);
		bwt->cnt_table[i] = x;
	}
}

static inline bwtint_t bwt_invPsi(const bwt_t *bwt, bwtint_t k) // compute inverse CSA
{
	bwtint_t x = k - (k > bwt->primary);
	x = bwt_B0(bwt, x);
	x = bwt->L2[x] + bwt_occ(bwt, k, x);
	return k == bwt->primary? 0 : x;
}

// bwt->bwt and bwt->occ must be precalculated
void bwt_cal_sa(bwt_t *bwt, int intv)
{
	bwtint_t isa, sa, i; // S(isa) = sa
	int intv_round = intv;

	kv_roundup32(intv_round);
	xassert(intv_round == intv, "SA sample interval is not a power of 2.");
	xassert(bwt->bwt, "bwt_t::bwt is not initialized.");

	if (bwt->sa) free(bwt->sa);
	bwt->sa_intv = intv;
	bwt->n_sa = (bwt->seq_len + intv) / intv;
	bwt->sa = (bwtint_t*)calloc(bwt->n_sa, sizeof(bwtint_t));
	// calculate SA value
	isa = 0; sa = bwt->seq_len;
	for (i = 0; i < bwt->seq_len; ++i) {
		if (isa % intv == 0) bwt->sa[isa/intv] = sa;
		--sa;
		isa = bwt_invPsi(bwt, isa);
	}
	if (isa % intv == 0) bwt->sa[isa/intv] = sa;
	bwt->sa[0] = (bwtint_t)-1; // before this line, bwt->sa[0] = bwt->seq_len
}

bwtint_t bwt_sa(const bwt_t *bwt, bwtint_t k)
{
	bwtint_t sa = 0, mask = bwt->sa_intv - 1;
	while (k & mask) {
		++sa;
		k = bwt_invPsi(bwt, k);
	}
	/* without setting bwt->sa[0] = -1, the following line should be
	   changed to (sa + bwt->sa[k/bwt->sa_intv]) % (bwt->seq_len + 1) */
	return sa + bwt->sa[k/bwt->sa_intv];
}

static inline int __occ_aux(uint64_t y, int c)
{
	// reduce nucleotide counting to bits counting
	y = ((c&2)? y : ~y) >> 1 & ((c&1)? y : ~y) & 0x5555555555555555ull;
	// count the number of 1s in y
	y = (y & 0x3333333333333333ull) + (y >> 2 & 0x3333333333333333ull);
	return ((y + (y >> 4)) & 0xf0f0f0f0f0f0f0full) * 0x101010101010101ull >> 56;
}

bwtint_t bwt_occ(const bwt_t *bwt, bwtint_t k, ubyte_t c)
{
	bwtint_t n;
	uint32_t *p, *end;

	if (k == bwt->seq_len) return bwt->L2[c+1] - bwt->L2[c];
	if (k == (bwtint_t)(-1)) return 0;
	k -= (k >= bwt->primary); // because $ is not in bwt

	// retrieve Occ at k/OCC_INTERVAL
	n = ((bwtint_t*)(p = bwt_occ_intv(bwt, k)))[c];
	p += sizeof(bwtint_t); // jump to the start of the first BWT cell

	// calculate Occ up to the last k/32
	end = p + (((k>>5) - ((k&~OCC_INTV_MASK)>>5))<<1);
	for (; p < end; p += 2) n += __occ_aux((uint64_t)p[0]<<32 | p[1], c);

	// calculate Occ
	n += __occ_aux(((uint64_t)p[0]<<32 | p[1]) & ~((1ull<<((~k&31)<<1)) - 1), c);
	if (c == 0) n -= ~k&31; // corrected for the masked bits

	return n;
}

// an analogy to bwt_occ() but more efficient, requiring k <= l
void bwt_2occ(const bwt_t *bwt, bwtint_t k, bwtint_t l, ubyte_t c, bwtint_t *ok, bwtint_t *ol)
{
	bwtint_t _k, _l;
	_k = (k >= bwt->primary)? k-1 : k;
	_l = (l >= bwt->primary)? l-1 : l;
	if (_l/OCC_INTERVAL != _k/OCC_INTERVAL || k == (bwtint_t)(-1) || l == (bwtint_t)(-1)) {
		*ok = bwt_occ(bwt, k, c);
		*ol = bwt_occ(bwt, l, c);
	} else {
		bwtint_t m, n, i, j;
		uint32_t *p;
		if (k >= bwt->primary) --k;
		if (l >= bwt->primary) --l;
		n = ((bwtint_t*)(p = bwt_occ_intv(bwt, k)))[c];
		p += sizeof(bwtint_t);
		// calculate *ok
		j = k >> 5 << 5;
		for (i = k/OCC_INTERVAL*OCC_INTERVAL; i < j; i += 32, p += 2)
			n += __occ_aux((uint64_t)p[0]<<32 | p[1], c);
		m = n;
		n += __occ_aux(((uint64_t)p[0]<<32 | p[1]) & ~((1ull<<((~k&31)<<1)) - 1), c);
		if (c == 0) n -= ~k&31; // corrected for the masked bits
		*ok = n;
		// calculate *ol
		j = l >> 5 << 5;
		for (; i < j; i += 32, p += 2)
			m += __occ_aux((uint64_t)p[0]<<32 | p[1], c);
		m += __occ_aux(((uint64_t)p[0]<<32 | p[1]) & ~((1ull<<((~l&31)<<1)) - 1), c);
		if (c == 0) m -= ~l&31; // corrected for the masked bits
		*ol = m;
	}
}

#define __occ_aux4(bwt, b)											\
	((bwt)->cnt_table[(b)&0xff] + (bwt)->cnt_table[(b)>>8&0xff]		\
	 + (bwt)->cnt_table[(b)>>16&0xff] + (bwt)->cnt_table[(b)>>24])

void bwt_occ4(const bwt_t *bwt, bwtint_t k, bwtint_t cnt[4])
{
	bwtint_t x;
	uint32_t *p, tmp, *end;
	if (k == (bwtint_t)(-1)) {
		memset(cnt, 0, 4 * sizeof(bwtint_t));
		return;
	}
	k -= (k >= bwt->primary); // because $ is not in bwt
	p = bwt_occ_intv(bwt, k);
	memcpy(cnt, p, 4 * sizeof(bwtint_t));
	p += sizeof(bwtint_t); // sizeof(bwtint_t) = 4*(sizeof(bwtint_t)/sizeof(uint32_t))
	end = p + ((k>>4) - ((k&~OCC_INTV_MASK)>>4)); // this is the end point of the following loop
	for (x = 0; p < end; ++p) x += __occ_aux4(bwt, *p);
	tmp = *p & ~((1U<<((~k&15)<<1)) - 1);
	x += __occ_aux4(bwt, tmp) - (~k&15);
	cnt[0] += x&0xff; cnt[1] += x>>8&0xff; cnt[2] += x>>16&0xff; cnt[3] += x>>24;
}

// an analogy to bwt_occ4() but more efficient, requiring k <= l
void bwt_2occ4(const bwt_t *bwt, bwtint_t k, bwtint_t l, bwtint_t cntk[4], bwtint_t cntl[4])
{
	bwtint_t _k, _l;
	_k = k - (k >= bwt->primary);
	_l = l - (l >= bwt->primary);

  //////////////////////////////////////////////////
  uint32_t *p_k,*p_l;  
	p_k = bwt_occ_intv(bwt,_k);
  p_l = bwt_occ_intv(bwt,_l);

  int RW=1;
  int RW_i;

  //First cacheline //
  *pInput = 0x00010021;  //Header
  pInput+=2;
  *pInput = _k & 0xffffffff;
  pInput++;  
  *pInput = (_k>>32) & 0xffffffff;  
  pInput++;
  *pInput = _l & 0xffffffff;
  pInput++;
  *pInput = (_l>>32) & 0xffffffff;
  pInput+= 11;    
  memcpy(pInput, p_k, 8 * sizeof(bwtint_t));
  pInput+= 16;
  memcpy(pInput, p_l, 8 * sizeof(bwtint_t));
  pInput = pInput-32; 
  RW = CCI_RW(3,3);
  //////////////////////////////////////////////////
  
  	
	if (_l>>OCC_INTV_SHIFT != _k>>OCC_INTV_SHIFT || k == (bwtint_t)(-1) || l == (bwtint_t)(-1)) {
		bwt_occ4(bwt, k, cntk);
		bwt_occ4(bwt, l, cntl);
	} else {
		bwtint_t x, y;
		uint32_t *p, tmp, *endk, *endl;
		k -= (k >= bwt->primary); // because $ is not in bwt
		l -= (l >= bwt->primary);
		p = bwt_occ_intv(bwt, k);
		memcpy(cntk, p, 4 * sizeof(bwtint_t));
		p += sizeof(bwtint_t); // sizeof(bwtint_t) = 4*(sizeof(bwtint_t)/sizeof(uint32_t))
		// prepare cntk[]
		endk = p + ((k>>4) - ((k&~OCC_INTV_MASK)>>4));
		endl = p + ((l>>4) - ((l&~OCC_INTV_MASK)>>4));
		for (x = 0; p < endk; ++p) x += __occ_aux4(bwt, *p);
		y = x;
		tmp = *p & ~((1U<<((~k&15)<<1)) - 1);
		x += __occ_aux4(bwt, tmp) - (~k&15);
		// calculate cntl[] and finalize cntk[]
		for (; p < endl; ++p) y += __occ_aux4(bwt, *p);
		tmp = *p & ~((1U<<((~l&15)<<1)) - 1);
		y += __occ_aux4(bwt, tmp) - (~l&15);
		memcpy(cntl, cntk, 4 * sizeof(bwtint_t));
		cntk[0] += x&0xff; cntk[1] += x>>8&0xff; cntk[2] += x>>16&0xff; cntk[3] += x>>24;
		cntl[0] += y&0xff; cntl[1] += y>>8&0xff; cntl[2] += y>>16&0xff; cntl[3] += y>>24;
	}
	
	//////////////////////////////////////////////////
  //bwtint_t cnt_final[8];
  bwtint_t cnt_final_k[4];
  bwtint_t cnt_final_l[4];
  memcpy(cnt_final_k, pOutput, 4 * sizeof(bwtint_t));
  memcpy(cnt_final_l, pOutput+8, 4 * sizeof(bwtint_t));  
  int error =0; 
  for(RW_i=0; RW_i<4; RW_i++) {
  	if(cnt_final_k[RW_i]!= cntk[RW_i]) error =1;
  	if(cnt_final_l[RW_i]!= cntl[RW_i]) error =1;
  }
  //for(RW_i=4; RW_i<7; RW_i++) if(cnt_final[RW_i]!= cntl[RW_i-4]) error =1;
  if(error){
	  FILE *test_RW;
	  test_RW = fopen("test_RW.txt", "a");
	  fprintf(test_RW,"error \n");
	  fclose(test_RW); 
	}
  //////////////////////////////////////////////////
  
/*
  //////////////////////////////////////////////////
  memcpy(cntk, pOutput, 4 * sizeof(bwtint_t));  
  memcpy(cntl, pOutput+8, 4 * sizeof(bwtint_t));  
  //////////////////////////////////////////////////
*/

}

int bwt_match_exact(const bwt_t *bwt, int len, const ubyte_t *str, bwtint_t *sa_begin, bwtint_t *sa_end)
{
	bwtint_t k, l, ok, ol;
	int i;
	k = 0; l = bwt->seq_len;
	for (i = len - 1; i >= 0; --i) {
		ubyte_t c = str[i];
		if (c > 3) return 0; // no match
		bwt_2occ(bwt, k - 1, l, c, &ok, &ol);
		k = bwt->L2[c] + ok + 1;
		l = bwt->L2[c] + ol;
		if (k > l) break; // no match
	}
	if (k > l) return 0; // no match
	if (sa_begin) *sa_begin = k;
	if (sa_end)   *sa_end = l;
	return l - k + 1;
}

int bwt_match_exact_alt(const bwt_t *bwt, int len, const ubyte_t *str, bwtint_t *k0, bwtint_t *l0)
{
	int i;
	bwtint_t k, l, ok, ol;
	k = *k0; l = *l0;
	for (i = len - 1; i >= 0; --i) {
		ubyte_t c = str[i];
		if (c > 3) return 0; // there is an N here. no match
		bwt_2occ(bwt, k - 1, l, c, &ok, &ol);
		k = bwt->L2[c] + ok + 1;
		l = bwt->L2[c] + ol;
		if (k > l) return 0; // no match
	}
	*k0 = k; *l0 = l;
	return l - k + 1;
}

/*********************
 * Bidirectional BWT *
 *********************/

// comaniac: Batched BWT utils.
void kv_push_bwtintv_t(bwtintv_v *v, bwtintv_t ik)
{
  if (v->n == v->m) {
	  v->m = v->m ? v->m << 1: 2;
	  v->a = (bwtintv_t*)realloc(v->a, sizeof(bwtintv_t) * v->m);
  }
  v->a[v->n++] = ik;

	return ;
}

// comanaic: Batched BWT process.
void bwt_forward_search_batched(smem_i **itr, int *x, bwtintv_v **curr, bwtintv_t *ik, bwtintv_t **ok, 
		int *min_intv, int batch_size, const int *done)
{
	int batch_idx, i, gi;

	int *local_done = (int *)malloc(sizeof(int) * batch_size);
	memcpy(local_done, done, sizeof(int) * batch_size);

	for (batch_idx = 0; batch_idx < batch_size; ++batch_idx)
		curr[batch_idx]->n = 0;

	for (gi = 1; gi < itr[0]->len; ++gi) {
		for (batch_idx = 0; batch_idx < batch_size; ++batch_idx) {
	    if (local_done[batch_idx])
  	    continue;

			i = gi + x[batch_idx];
			if (i >= itr[0]->len)
				continue;

      if (itr[batch_idx]->query[i] < 4) { // an A/C/G/T base
        int c = 3 - itr[batch_idx]->query[i]; // complement of q[i]
				bwtint_t tk[4], tl[4];
	
				// bwt_extend =====		
				int j;
				bwt_2occ4(itr[batch_idx]->bwt, ik[batch_idx].x[1] - 1, 
									ik[batch_idx].x[1] - 1 + ik[batch_idx].x[2], tk, tl);
				
				for (j = 0; j != 4; ++j) {
					ok[batch_idx][j].x[1] = itr[batch_idx]->bwt->L2[j] + 1 + tk[j];
					ok[batch_idx][j].x[2] = tl[j] - tk[j];
				}
				ok[batch_idx][3].x[0] = ik[batch_idx].x[0] + 
					(ik[batch_idx].x[1] <= itr[batch_idx]->bwt->primary && 
					 ik[batch_idx].x[1] + ik[batch_idx].x[2] - 1 >= itr[batch_idx]->bwt->primary);
				ok[batch_idx][2].x[0] = ok[batch_idx][3].x[0] + ok[batch_idx][3].x[2];
				ok[batch_idx][1].x[0] = ok[batch_idx][2].x[0] + ok[batch_idx][2].x[2];
				ok[batch_idx][0].x[0] = ok[batch_idx][1].x[0] + ok[batch_idx][1].x[2];
				// bwt_extend =====

        if (ok[batch_idx][c].x[2] != ik[batch_idx].x[2]) { // change of the interval size
          kv_push_bwtintv_t(curr[batch_idx], ik[batch_idx]);
          if (ok[batch_idx][c].x[2] < min_intv[batch_idx]) {
						local_done[batch_idx] = 1;
            continue;
					}
        }
        ik[batch_idx] = ok[batch_idx][c];
        ik[batch_idx].info = i + 1;
      } else { // an ambiguous base
        kv_push_bwtintv_t(curr[batch_idx], ik[batch_idx]);
				local_done[batch_idx] = 1;
        continue;
      }
    }
  }	

	for (i = 0; i < batch_size; ++i)
    if (local_done[i] == 0)
      kv_push_bwtintv_t(curr[i], ik[i]); // push the last interval if we reach the end

	free(local_done);
	return ;
}

// comaniac: Batched BWT process.
void bwt_backward_search_batched(smem_i **itr, int *x, bwtintv_v ***intv, bwtintv_t *ik, bwtintv_t **ok, 
		bwtintv_v **mem, int *min_intv, int batch_size, const int *done)
{
	#define PREV	0
	#define CURR	1
	#define INV(t) (t == PREV)? CURR: PREV

	int batch_idx, i, j;
	int token;

	for (batch_idx = 0; batch_idx < batch_size; ++batch_idx) {
		if (done[batch_idx])
			continue;

		token = PREV;
		for (i = x[batch_idx] - 1; i >= -1; --i) { // backward search for MEMs
			int c = i < 0	? -1 : 
						itr[batch_idx]->query[i] < 4? itr[batch_idx]->query[i] : 
						-1; // c==-1 if i<0 or q[i] is an ambiguous base

			for (j = 0, intv[token][batch_idx]->n = 0; j < intv[INV(token)][batch_idx]->n; ++j) {
				bwtintv_t *p = &intv[INV(token)][batch_idx]->a[j];

				// bwt_extend =====
				bwtint_t tk[4], tl[4];
				int k;
				bwt_2occ4(itr[batch_idx]->bwt, p->x[0] - 1, p->x[0] - 1 + p->x[2], tk, tl);
				for (k = 0; k != 4; ++k) {
					ok[batch_idx][k].x[0] = itr[batch_idx]->bwt->L2[k] + 1 + tk[k];
					ok[batch_idx][k].x[2] = tl[k] - tk[k];
				}
				ok[batch_idx][3].x[1] = p->x[1] + 
					(p->x[0] <= itr[batch_idx]->bwt->primary && 
					 p->x[0] + p->x[2] - 1 >= itr[batch_idx]->bwt->primary);
				ok[batch_idx][2].x[1] = ok[batch_idx][3].x[0] + ok[batch_idx][3].x[2];
				ok[batch_idx][1].x[1] = ok[batch_idx][2].x[0] + ok[batch_idx][2].x[2];
				ok[batch_idx][0].x[1] = ok[batch_idx][1].x[0] + ok[batch_idx][1].x[2];
				// bwt_extend =====

				if (c < 0 || ok[batch_idx][c].x[2] < min_intv[batch_idx]) { 
				// keep the hit if reaching the beginning or an ambiguous base or the intv is small enough
					if (intv[token][batch_idx]->n == 0) { // test curr->n>0 to make sure there are no longer matches
						if (mem[batch_idx]->n == 0 || 
								i + 1 < mem[batch_idx]->a[mem[batch_idx]->n-1].info>>32) { // skip contained matches
							ik[batch_idx] = *p; 
							ik[batch_idx].info |= (uint64_t)(i + 1)<<32;
							kv_push_bwtintv_t(mem[batch_idx], ik[batch_idx]);
						}
					} // otherwise the match is contained in another longer match
				} else if (intv[token][batch_idx]->n == 0 || 
									ok[batch_idx][c].x[2] != intv[token][batch_idx]->a[intv[token][batch_idx]->n-1].x[2]) {
					ok[batch_idx][c].info = p->info;
					kv_push_bwtintv_t(intv[token][batch_idx], ok[batch_idx][c]);
				}
			}
			if (intv[token][batch_idx]->n == 0) 
				break;
			token = INV(token);

		} // end for i
	} // end for batch_idx
	// =============

	return ;
}

void bwt_extend(const bwt_t *bwt, const bwtintv_t *ik, bwtintv_t ok[4], int is_back)
{
	bwtint_t tk[4], tl[4];
	int i;
	bwt_2occ4(bwt, ik->x[!is_back] - 1, ik->x[!is_back] - 1 + ik->x[2], tk, tl);
	for (i = 0; i != 4; ++i) {
		ok[i].x[!is_back] = bwt->L2[i] + 1 + tk[i];
		ok[i].x[2] = tl[i] - tk[i];
	}
	ok[3].x[is_back] = ik->x[is_back] + (ik->x[!is_back] <= bwt->primary && ik->x[!is_back] + ik->x[2] - 1 >= bwt->primary);
	ok[2].x[is_back] = ok[3].x[is_back] + ok[3].x[2];
	ok[1].x[is_back] = ok[2].x[is_back] + ok[2].x[2];
	ok[0].x[is_back] = ok[1].x[is_back] + ok[1].x[2];
}

static void bwt_reverse_intvs(bwtintv_v *p)
{
	if (p->n > 1) {
		int j;
		for (j = 0; j < p->n>>1; ++j) {
			bwtintv_t tmp = p->a[p->n - 1 - j];
			p->a[p->n - 1 - j] = p->a[j];
			p->a[j] = tmp;
		}
	}
}

// comaniac: Batched BWT process.
void bwt_smem1_batched(smem_i **itr, int *ori_start, int *max_i, int start_width, 
	int is_middle, int batch_size, const int *done, int bwt_batched_status)
{
	#define PREV	0
	#define CURR	1

	int batch_idx, i;

	static __thread int *min_intv;
	static __thread int *x;
	static __thread bwtintv_v **mem;
	static __thread int *local_done;

	static __thread bwtintv_t *ik;
	static __thread bwtintv_t **ok;
	static __thread bwtintv_v ***intv;
	static __thread bwtintv_v **a;

	if (bwt_batched_status == BWT_BATCHED_INIT) {
		min_intv = (int *)malloc(sizeof(int) * batch_size);
		x = (int *)malloc(sizeof(int) * batch_size);
		mem = (bwtintv_v **)malloc(sizeof(bwtintv_v *) * batch_size);
		local_done = (int *)malloc(sizeof(int) * batch_size);
	
		ik = (bwtintv_t *)malloc(sizeof(bwtintv_t) * batch_size);
		ok = (bwtintv_t **)malloc(sizeof(bwtintv_t *) * batch_size);;
		for (i = 0; i < batch_size; ++i)
			ok[i] = (bwtintv_t *)malloc(sizeof(bwtintv_t) * 4);
	
		intv = (bwtintv_v ***)malloc(sizeof(bwtintv_v **) * 2);
		for (i = 0; i < 2; ++i)	
			intv[i] = (bwtintv_v **)malloc(sizeof(bwtintv_v *) * batch_size);
	
		a = (bwtintv_v **)malloc(sizeof(bwtintv_v *) * batch_size);
		for (i = 0; i < batch_size; ++i)
			a[i] = (bwtintv_v *)malloc(sizeof(bwtintv_v) * 2);
		return ;
	} else if (bwt_batched_status == BWT_BATCHED_FREE) {
		free(local_done);
		free(ik);
		for (i = 0; i < 2; ++i)
			free(intv[i]);
		free(intv);
		for (i = 0; i < batch_size; ++i)
			free(a[i]);
		free(a);
		for (i = 0; i < batch_size; ++i)
			free(ok[i]);
		free(ok);
		free(min_intv);
		free(x);
		return ;
	}

	// comaniac: Init here
	memcpy(local_done, done, sizeof(int) * batch_size);

	if (!is_middle) {
		memcpy(x, ori_start, sizeof(int) * batch_size);
		for (batch_idx = 0; batch_idx < batch_size; ++batch_idx)
			mem[batch_idx] = itr[batch_idx]->matches;
	}
	else {
		for (batch_idx = 0; batch_idx < batch_size; ++batch_idx) {
			bwtintv_t *p = &itr[batch_idx]->matches->a[max_i[batch_idx]];
			x[batch_idx] = ((uint32_t)p->info + (p->info>>32))>>1;
			mem[batch_idx] = itr[batch_idx]->sub;
		}
	}

	for (batch_idx = 0; batch_idx < batch_size; ++batch_idx) {
		if (local_done[batch_idx])
			continue;

		mem[batch_idx]->n = 0;

		if (itr[batch_idx]->query[x[batch_idx]] > 3) {
			local_done[batch_idx] = 1;
			if (!is_middle)
				itr[batch_idx]->start = x[batch_size] + 1;
			continue;
		}

		// the interval size should be at least 1
		if (!is_middle)
			min_intv[batch_idx] = start_width;
		else
			min_intv[batch_idx] = itr[batch_idx]->matches->a[max_i[batch_idx]].x[2] + 1;
		if (min_intv[batch_idx] < 1) 
			min_intv[batch_idx] = 1;

		kv_init(a[batch_idx][0]);
		kv_init(a[batch_idx][1]);

		// use the temporary vector if provided
		intv[PREV][batch_idx] = itr[batch_idx]->tmpvec && itr[batch_idx]->tmpvec[0]? itr[batch_idx]->tmpvec[0] : &a[batch_idx][0]; 
		intv[CURR][batch_idx] = itr[batch_idx]->tmpvec && itr[batch_idx]->tmpvec[1]? itr[batch_idx]->tmpvec[1] : &a[batch_idx][1];
		bwt_set_intv(itr[batch_idx]->bwt, itr[batch_idx]->query[x[batch_idx]], ik[batch_idx]); // the initial interval of a single base
		ik[batch_idx].info = x[batch_idx] + 1;
	}

	bwt_forward_search_batched(itr, x, intv[CURR], ik, ok, min_intv, batch_size, local_done);

	for (batch_idx = 0; batch_idx < batch_size; ++batch_idx) {
		if (local_done[batch_idx])
			continue;

		// s.t. smaller intervals (i.e. longer matches) visited first
		bwt_reverse_intvs(intv[CURR][batch_idx]);

		if (!is_middle)
			itr[batch_idx]->start = intv[CURR][batch_idx]->a[0].info;
	}

	bwt_backward_search_batched(itr, x, intv, ik, ok, mem, min_intv, batch_size, local_done);

	for (batch_idx = 0; batch_idx < batch_size; ++batch_idx) {
		if (local_done[batch_idx])
			continue;

		bwt_reverse_intvs(mem[batch_idx]); // s.t. sorted by the start coordinate

		if (itr[batch_idx]->tmpvec == 0 || itr[batch_idx]->tmpvec[0] == 0) 
			free(a[batch_idx][0].a);
		if (itr[batch_idx]->tmpvec == 0 || itr[batch_idx]->tmpvec[1] == 0) 
			free(a[batch_idx][1].a);
	}

	return ;
}

int bwt_smem1(const bwt_t *bwt, int len, const uint8_t *q, int x, int min_intv, bwtintv_v *mem, bwtintv_v *tmpvec[2])
{
	int i, j, c, ret;
	bwtintv_t ik, ok[4];
	bwtintv_v a[2], *prev, *curr, *swap;

	mem->n = 0;
	if (q[x] > 3) return x + 1;
	if (min_intv < 1) min_intv = 1; // the interval size should be at least 1
	kv_init(a[0]); kv_init(a[1]);
	prev = tmpvec && tmpvec[0]? tmpvec[0] : &a[0]; // use the temporary vector if provided
	curr = tmpvec && tmpvec[1]? tmpvec[1] : &a[1];
	bwt_set_intv(bwt, q[x], ik); // the initial interval of a single base
	ik.info = x + 1;

	for (i = x + 1, curr->n = 0; i < len; ++i) { // forward search
		if (q[i] < 4) { // an A/C/G/T base
			c = 3 - q[i]; // complement of q[i]
			bwt_extend(bwt, &ik, ok, 0);
			if (ok[c].x[2] != ik.x[2]) { // change of the interval size
				kv_push(bwtintv_t, *curr, ik);
				if (ok[c].x[2] < min_intv) break; // the interval size is too small to be extended further
			}
			ik = ok[c]; ik.info = i + 1;
		} else { // an ambiguous base
			kv_push(bwtintv_t, *curr, ik);
			break; // always terminate extension at an ambiguous base; in this case, i<len always stands
		}
	}
	if (i == len) kv_push(bwtintv_t, *curr, ik); // push the last interval if we reach the end
	bwt_reverse_intvs(curr); // s.t. smaller intervals (i.e. longer matches) visited first
	ret = curr->a[0].info; // this will be the returned value
	swap = curr; curr = prev; prev = swap;

	for (i = x - 1; i >= -1; --i) { // backward search for MEMs
		c = i < 0? -1 : q[i] < 4? q[i] : -1; // c==-1 if i<0 or q[i] is an ambiguous base
		for (j = 0, curr->n = 0; j < prev->n; ++j) {
			bwtintv_t *p = &prev->a[j];
			bwt_extend(bwt, p, ok, 1);
			if (c < 0 || ok[c].x[2] < min_intv) { // keep the hit if reaching the beginning or an ambiguous base or the intv is small enough
				if (curr->n == 0) { // test curr->n>0 to make sure there are no longer matches
					if (mem->n == 0 || i + 1 < mem->a[mem->n-1].info>>32) { // skip contained matches
						ik = *p; ik.info |= (uint64_t)(i + 1)<<32;
						kv_push(bwtintv_t, *mem, ik);
					}
				} // otherwise the match is contained in another longer match
			} else if (curr->n == 0 || ok[c].x[2] != curr->a[curr->n-1].x[2]) {
				ok[c].info = p->info;
				kv_push(bwtintv_t, *curr, ok[c]);
			}
		}
		if (curr->n == 0) break;
		swap = curr; curr = prev; prev = swap;
	}
	bwt_reverse_intvs(mem); // s.t. sorted by the start coordinate

	if (tmpvec == 0 || tmpvec[0] == 0) free(a[0].a);
	if (tmpvec == 0 || tmpvec[1] == 0) free(a[1].a);
	return ret;
}

/*************************
 * Read/write BWT and SA *
 *************************/

void bwt_dump_bwt(const char *fn, const bwt_t *bwt)
{
	FILE *fp;
	fp = xopen(fn, "wb");
	err_fwrite(&bwt->primary, sizeof(bwtint_t), 1, fp);
	err_fwrite(bwt->L2+1, sizeof(bwtint_t), 4, fp);
	err_fwrite(bwt->bwt, 4, bwt->bwt_size, fp);
	err_fflush(fp);
	err_fclose(fp);
}

void bwt_dump_sa(const char *fn, const bwt_t *bwt)
{
	FILE *fp;
	fp = xopen(fn, "wb");
	err_fwrite(&bwt->primary, sizeof(bwtint_t), 1, fp);
	err_fwrite(bwt->L2+1, sizeof(bwtint_t), 4, fp);
	err_fwrite(&bwt->sa_intv, sizeof(bwtint_t), 1, fp);
	err_fwrite(&bwt->seq_len, sizeof(bwtint_t), 1, fp);
	err_fwrite(bwt->sa + 1, sizeof(bwtint_t), bwt->n_sa - 1, fp);
	err_fflush(fp);
	err_fclose(fp);
}

static bwtint_t fread_fix(FILE *fp, bwtint_t size, void *a)
{ // Mac/Darwin has a bug when reading data longer than 2GB. This function fixes this issue by reading data in small chunks
	const int bufsize = 0x1000000; // 16M block
	bwtint_t offset = 0;
	while (size) {
		int x = bufsize < size? bufsize : size;
		if ((x = err_fread_noeof(a + offset, 1, x, fp)) == 0) break;
		size -= x; offset += x;
	}
	return offset;
}

void bwt_restore_sa(const char *fn, bwt_t *bwt)
{
	char skipped[256];
	FILE *fp;
	bwtint_t primary;

	fp = xopen(fn, "rb");
	err_fread_noeof(&primary, sizeof(bwtint_t), 1, fp);
	xassert(primary == bwt->primary, "SA-BWT inconsistency: primary is not the same.");
	err_fread_noeof(skipped, sizeof(bwtint_t), 4, fp); // skip
	err_fread_noeof(&bwt->sa_intv, sizeof(bwtint_t), 1, fp);
	err_fread_noeof(&primary, sizeof(bwtint_t), 1, fp);
	xassert(primary == bwt->seq_len, "SA-BWT inconsistency: seq_len is not the same.");

	bwt->n_sa = (bwt->seq_len + bwt->sa_intv) / bwt->sa_intv;
	bwt->sa = (bwtint_t*)calloc(bwt->n_sa, sizeof(bwtint_t));
	bwt->sa[0] = -1;

	fread_fix(fp, sizeof(bwtint_t) * (bwt->n_sa - 1), bwt->sa + 1);
	err_fclose(fp);
}

bwt_t *bwt_restore_bwt(const char *fn)
{
	bwt_t *bwt;
	FILE *fp;

	bwt = (bwt_t*)calloc(1, sizeof(bwt_t));
	fp = xopen(fn, "rb");
	err_fseek(fp, 0, SEEK_END);
	bwt->bwt_size = (err_ftell(fp) - sizeof(bwtint_t) * 5) >> 2;
	bwt->bwt = (uint32_t*)calloc(bwt->bwt_size, 4);
	err_fseek(fp, 0, SEEK_SET);
	err_fread_noeof(&bwt->primary, sizeof(bwtint_t), 1, fp);
	err_fread_noeof(bwt->L2+1, sizeof(bwtint_t), 4, fp);
	fread_fix(fp, bwt->bwt_size<<2, bwt->bwt);
	bwt->seq_len = bwt->L2[4];
	err_fclose(fp);
	bwt_gen_cnt_table(bwt);

	return bwt;
}

void bwt_destroy(bwt_t *bwt)
{
	if (bwt == 0) return;
	free(bwt->sa); free(bwt->bwt);
	free(bwt);
}
