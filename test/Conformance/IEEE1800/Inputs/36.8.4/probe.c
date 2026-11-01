#include "sv_vpi_user.h"
static PLI_INT32 calltf(PLI_BYTE8 *data){return data!=0;}
static PLI_INT32 compiletf(PLI_BYTE8 *data){return data!=0;}
static PLI_INT32 sizetf(PLI_BYTE8 *data){return 8;}
static s_vpi_systf_data data={.type=vpiSysFunc,.sysfunctype=vpiSizedFunc,.tfname="$probe",.calltf=calltf,.compiletf=compiletf,.sizetf=sizetf,.user_data=(PLI_BYTE8*)"probe"};
