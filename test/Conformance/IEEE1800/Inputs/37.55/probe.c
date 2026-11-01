#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
// 5.6.1: the escaped spelling \a (with its terminating space) names the same identifier as a.
static void plain(const char *s) {
  for (; *s; s++) {
    if (*s != '\\') {
      putchar(*s);
      continue;
    }
    while (*++s && *s != ' ')
      putchar(*s);
    if (!*s)
      break;
  }
}
void probe(void) {
  vpiHandle procs = vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0));
  vpiHandle init = procs ? vpi_scan(procs) : 0;
  vpiHandle body = init ? vpi_handle(vpiStmt, init) : 0;
  vpiHandle s, it = body ? vpi_iterate(vpiStmt, body) : 0;
  if (!it) {
    printf("no statements\n");
    return;
  }
  while ((s = vpi_scan(it))) {
    int type = vpi_get(vpiType, s);
    if (type == vpiFuncCall || type == vpiSysTaskCall)
      continue;
    printf("%s", str(vpiName, s));
    printf(" type=%s", str(vpiType, s));
    printf(" deferred=%d final=%d expr=", vpi_get(vpiIsDeferred, s) > 0, vpi_get(vpiIsFinal, s) > 0);
    vpiHandle expr = vpi_handle(vpiExpr, s);
    plain(str(vpiDecompile, expr));
    s_vpi_value v = {.format = vpiIntVal};
    if (expr)
      vpi_get_value(expr, &v);
    printf(" value=%d", expr ? v.value.integer : -1);
    printf(" stmt=%s", str(vpiType, vpi_handle(vpiStmt, s)));
    printf(" else=%s\n", str(vpiType, vpi_handle(vpiElseStmt, s)));
  }
}
