// hello.c
// baby steps VPI module
// defines $hello, which just says "hi there"
// (C) 2015 Riad S. Wahby <rsw@cs.nyu.edu>

#include "hello.h"

static int hello_compiletf(PLI_BYTE8 *user_data) {
    (void) user_data;

    return 0;
}

static int hello_calltf(PLI_BYTE8 *user_data) {
    (void) user_data;

    vpi_printf("hi there\n");
    return 0;
}

void hello_register(void) {
    s_vpi_systf_data tf_data = 
        { .type = vpiSysTask
        , .tfname = "$hello"
        , .calltf = hello_calltf
        , .compiletf = hello_compiletf
        , .sizetf = 0
        , .user_data = 0
        };

    vpi_register_systf(&tf_data);
}
