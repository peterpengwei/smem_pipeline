## Copyright (c) 2005-2015, Intel Corporation
##
## Redistribution  and  use  in source  and  binary  forms,  with  or  without
## modification, are permitted provided that the following conditions are met:
##
## * Redistributions of  source code  must retain the  above copyright notice,
##   this list of conditions and the following disclaimer.
## * Redistributions in binary form must reproduce the above copyright notice,
##   this list of conditions and the following disclaimer in the documentation
##   and/or other materials provided with the distribution.
## * Neither the name  of Intel Corporation  nor the names of its contributors
##   may be used to  endorse or promote  products derived  from this  software
##   without specific prior written permission.
##
## THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
## AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,  BUT NOT LIMITED TO,  THE
## IMPLIED WARRANTIES OF  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
## ARE DISCLAIMED.  IN NO EVENT  SHALL THE COPYRIGHT OWNER  OR CONTRIBUTORS BE
## LIABLE  FOR  ANY  DIRECT,  INDIRECT,  INCIDENTAL,  SPECIAL,  EXEMPLARY,  OR
## CONSEQUENTIAL  DAMAGES  (INCLUDING,  BUT  NOT LIMITED  TO,  PROCUREMENT  OF
## SUBSTITUTE GOODS OR SERVICES;  LOSS OF USE,  DATA, OR PROFITS;  OR BUSINESS
## INTERRUPTION)  HOWEVER CAUSED  AND ON ANY THEORY  OF LIABILITY,  WHETHER IN
## CONTRACT,  STRICT LIABILITY,  OR TORT  (INCLUDING NEGLIGENCE  OR OTHERWISE)
## ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,  EVEN IF ADVISED OF THE
## POSSIBILITY OF SUCH DAMAGE.
##****************************************************************************
##     Intel(R) Accelerator Abstraction Layer Library Software Developer
##        Kit (SDK)
##  Content:
##     samples/Hello_SPL_LB/Makefile
##  Author:
##     Tim Whisonant, Intel Corporation
##     Joseph Grecco, Intel Corporation
##  History:
##     06/15/2015    JG   Initial version based off of canonical sample makefile
##******************************************************************************
CPPFLAGS ?=
CXX      ?= g++
LDFLAGS  ?=

ifeq (,$(CFLAGS))
CFLAGS = -g -O2
endif

ifneq (,$(ndebug))
else
CPPFLAGS += -DENABLE_DEBUG=1 -D ASE_DEBUG=1
endif
ifneq (,$(nassert))
else
CPPFLAGS += -DENABLE_ASSERT=1
endif

ifeq (,$(DESTDIR))
ifneq (,$(prefix))
CPPFLAGS += -I$(prefix)/include
LDFLAGS  += -L$(prefix)/lib -Wl,-rpath-link -Wl,$(prefix)/lib -Wl,-rpath -Wl,$(prefix)/lib \
            -L$(prefix)/lib64 -Wl,-rpath-link -Wl,$(prefix)/lib64 -Wl,-rpath -Wl,$(prefix)/lib64
endif
else
ifeq (,$(prefix))
prefix = /usr/local
endif
CPPFLAGS += -I$(DESTDIR)$(prefix)/include
LDFLAGS  += -L$(DESTDIR)$(prefix)/lib -Wl,-rpath-link -Wl,$(prefix)/lib -Wl,-rpath -Wl,$(DESTDIR)$(prefix)/lib \
            -L$(DESTDIR)$(prefix)/lib64 -Wl,-rpath-link -Wl,$(prefix)/lib64 -Wl,-rpath -Wl,$(DESTDIR)$(prefix)/lib64
endif

all: helloSPLlb 

helloSPLlb: libbwa.a $(ROBJS) HelloSPLLB.o
	##$(CXX) -g -O2 -o helloSPLlb HelloSPLLB.o $(LDFLAGS) -lOSAL -lAAS -lxlrt -L. -lbwa $(LIBS)
	$(CXX) -g -O2 -o helloSPLlb HelloSPLLB.o $(LDFLAGS) -lOSAL -lAAS -laalrt -L. -lbwa $(LIBS)

HelloSPLLB.o: HelloSPLLB.cpp  Makefile
	$(CXX) $(CPPFLAGS) -D__AAL_USER__=1  -g -O2 -c -o HelloSPLLB.o HelloSPLLB.cpp 

CC=			gcc
CFLAGS=		-g -Wall -Wno-unused-function -O2
WRAP_MALLOC=-DUSE_MALLOC_WRAPPERS
AR=			ar
DFLAGS=	-DHAVE_PTHREAD $(WRAP_MALLOC)
path = -rpath
LIBS = -lrt -lltdl -lpthread -lm -lz

ifeq (,$(pe))
DFLAGS += -DPE_NUM=16
endif
ifeq (,$(log))
DFLAGS += -DLOG_LEVEL=1
else
DFLAGS += -DLOG_LEVEL=2
endif
ifneq (,$(bypass))
DFLAGS += -DDEBUG_BYPASS
endif
ifneq (,$(sw))
DFLAGS += -DUSE_SW
endif
ifneq (,$(verify))
DFLAGS += -DUSE_SW_VERIFY
endif

.SUFFIXES:.c .o .cc
.c.o:
		$(CC) -c $(CFLAGS) $(DFLAGS) $(INCLUDES) $< -o $@

ROBJS= kthread.o kthread_batch.o ksw.o \
       bwt.o bntseq.o bwa.o bwamem.o bwamem_pair.o malloc_wrap.o \
       QSufSort.o bwt_gen.o bwase.o bwaseqio.o bwtgap.o bwtaln.o bamlite.o \
			 is.o bwtindex.o bwape.o kopen.o pemerge.o \
			 bwtsw2_core.o bwtsw2_main.o bwtsw2_aux.o bwt_lite.o \
			 bwtsw2_chain.o fastmap.o bwtsw2_pair.o top.o

libbwa.a:$(ROBJS)
		$(AR) -csru $@ $(ROBJS)
	
clean:
	rm -f *.o *.a *.la helloSPLlb HelloSPLLB.o

.PHONY:all clean
