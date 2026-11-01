#include "sv_vpi_user.h"
int covered(void) { return vpi_get(vpiToggleCoverage, vpi_handle_by_name("top", 0)); }
int control(int code) {
  static const int codes[] = {vpiCoverageStart, vpiCoverageStop, vpiCoverageReset, vpiCoverageCheck};
  return vpi_control(codes[code], vpiToggleCoverage, vpi_handle_by_name("top", 0));
}
