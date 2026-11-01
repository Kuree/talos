#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static void concurrent(const char *name) {
  vpiHandle a = vpi_handle_by_name(name, 0);
  printf("%s type=%s", name, str(vpiType, a));
  printf(" full=%s", str(vpiFullName, a));
  if (!a) {
    printf("\n");
    return;
  }
  printf(" inferred=%d", vpi_get(vpiIsClockInferred, a));
  printf(" event=%s", str(vpiDecompile, vpi_handle(vpiClockingEvent, a)));
  printf(" disable=%s", str(vpiDecompile, vpi_handle(vpiDisableCondition, a)));
  printf(" property=%s", str(vpiType, vpi_handle(vpiProperty, a)));
  printf(" else=%s\n", str(vpiType, vpi_handle(vpiElseStmt, a)));
}
static void cover(const char *name) {
  vpiHandle a = vpi_handle_by_name(name, 0);
  printf("%s type=%s", name, str(vpiType, a));
  printf(" cover_sequence=%d\n", a ? vpi_get(vpiIsCoverSequence, a) : -1);
}
void probe(void) {
  concurrent("top.explicit_a");
  concurrent("top.inferred_a");
  cover("top.cov_s");
  cover("top.cov_p");
}
