#include "svdpi.h"
extern int wait_sv(void);static int ok;
int call_c(void){int r=wait_sv();ok=(r==1 && svIsDisabledState());return r;}
int status(void){return ok;}
