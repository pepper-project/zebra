// hello.h
// baby steps VPI module (header)
// defines $hello, which just says "hi there"
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

#include <stdio.h>
#include <stdlib.h>

#include <vpi_user.h>
// for ncverilog only
#ifdef HAVE_VPI_USER_CDS_H
#include <vpi_user_cds.h>
#endif

static int hello_compiletf(PLI_BYTE8 *user_data);
static int hello_calltf(PLI_BYTE8 *user_data);
void hello_register(void);

void (*vlog_startup_routines[])(void) = { hello_register, 0 };
