#include "sv_vpi_user.h"
#include "svdpi.h"
#include <string.h>

int twice(int x) { return 2 * x; }

static int matches(const char *name, int access, int pure, int context,
                   int spec, const char *identifier) {
  vpiHandle h = vpi_handle_by_name((PLI_BYTE8 *)name, NULL);
  if (!h)
    return 0;
  const char *c_name = vpi_get_str(vpiDPICIdentifier, h);
  return c_name && strcmp(c_name, identifier) == 0 &&
         vpi_get(vpiAccessType, h) == access &&
         vpi_get(vpiDPIPure, h) == pure &&
         vpi_get(vpiDPIContext, h) == context && vpi_get(vpiDPICStr, h) == spec;
}

int check_properties(void) {
  return svGetScope() && vpi_handle_by_name((PLI_BYTE8 *)"top", NULL) &&
         matches("top.probe", vpiDPIImportAcc, 0, 1, vpiDPIC,
                 "check_properties") &&
         matches("top.double_it", vpiDPIImportAcc, 1, 0, vpiDPI, "twice") &&
         matches("top.identity", vpiDPIExportAcc, 0, 0, vpiDPIC, "sv_identity");
}
