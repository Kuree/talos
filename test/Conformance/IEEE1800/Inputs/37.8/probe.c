#include "sv_vpi_user.h"
#include <stdio.h>
static void list(int relation, const char *label, vpiHandle tf) {
  vpiHandle it = vpi_iterate(relation, tf);
  for (vpiHandle h; it && (h = vpi_scan(it));)
    printf(" %s=%s", label, vpi_get_str(vpiFullName, h));
}
void probe(void) {
  vpiHandle it = vpi_iterate(vpiInterfaceTfDecl, vpi_handle_by_name("top.b", 0));
  for (vpiHandle tf; it && (tf = vpi_scan(it));) {
    int access = vpi_get(vpiAccessType, tf);
    printf("tf access=%s", access == vpiExternAcc ? "vpiExternAcc" : access == vpiForkJoinAcc ? "vpiForkJoinAcc" : "other");
    list(vpiTask, "task", tf);
    list(vpiFunction, "function", tf);
    printf("\n");
  }
}
