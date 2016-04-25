#include <vpi_user.h>
// for ncverilog only
#ifdef HAVE_VPI_USER_CDS_H
#include <vpi_user_cds.h>
#endif

#include <stdbool.h>

#include "util.h"


PLI_INT32 cmt_init_comp(PLI_BYTE8 *user_data);
PLI_INT32 cmt_init_size(PLI_BYTE8 *user_data);

PLI_INT32 cmt_request_comp(PLI_BYTE8 *user_data);

PLI_INT32 cmt_send_comp(PLI_BYTE8 *user_data);

