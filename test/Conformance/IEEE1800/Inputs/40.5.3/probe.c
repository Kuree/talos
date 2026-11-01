#include "sv_vpi_user.h"
int act(int code) {
  static const int codes[] = {vpiCoverageStart, vpiCoverageStop, vpiCoverageReset, vpiCoverageCheck};
  return vpi_control(codes[code], vpiToggleCoverage, vpi_handle_by_name("top.d", 0));
}
int save_as(const char *name) { return vpi_control(vpiCoverageSave, vpiToggleCoverage, name); }
int merge_from(const char *name) { return vpi_control(vpiCoverageMerge, vpiToggleCoverage, name); }
