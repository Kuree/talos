#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
void probe(void) {
  vpiHandle it = vpi_iterate(vpiSequenceDecl, vpi_handle_by_name("top", 0));
  vpiHandle s = it ? vpi_scan(it) : 0;
  printf("decl type=%s", str(vpiType, s));
  printf(" name=%s\n", str(vpiName, s));
  if (!s)
    return;
  printf("full=%s\n", str(vpiFullName, s));
  vpiHandle f, formals = vpi_iterate(vpiSeqFormalDecl, s);
  if (formals)
    while ((f = vpi_scan(formals))) {
      int dir = vpi_get(vpiDirection, f);
      printf("formal %s nodir=%d input=%d typed=%d", str(vpiName, f), dir == vpiNoDirection, dir == vpiInput,
             vpi_handle(vpiTypespec, f) != 0);
      printf(" default=%s\n", str(vpiDecompile, vpi_handle(vpiExpr, f)));
    }
  vpiHandle v, vars = vpi_iterate(vpiVariables, s);
  if (vars)
    while ((v = vpi_scan(vars)))
      printf("variable %s\n", str(vpiName, v));
  vpiHandle expr = vpi_handle(vpiExpr, s);
  printf("expr=%s cycle_delay=%d\n", str(vpiType, expr), expr && vpi_get(vpiOpType, expr) == vpiCycleDelayOp);
}
