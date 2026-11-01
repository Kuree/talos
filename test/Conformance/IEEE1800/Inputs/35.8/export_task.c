#include "svdpi.h"
extern int sv_export_wait(int *out);
int c35_export_task(int *out) { return sv_export_wait(out); }
