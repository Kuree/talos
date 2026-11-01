#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
void probe(void) {
  vpiHandle it = vpi_iterate(vpiPropertyDecl, vpi_handle_by_name("top", 0));
  vpiHandle p = it ? vpi_scan(it) : 0;
  printf("decl type=%s", str(vpiType, p));
  printf(" name=%s\n", str(vpiName, p));
  if (p) {
    printf("full=%s\n", str(vpiFullName, p));
    vpiHandle f, formals = vpi_iterate(vpiPropFormalDecl, p);
    if (formals)
      while ((f = vpi_scan(formals))) {
        int dir = vpi_get(vpiDirection, f);
        printf("formal %s nodir=%d input=%d typed=%d", str(vpiName, f), dir == vpiNoDirection, dir == vpiInput,
               vpi_handle(vpiTypespec, f) != 0);
        printf(" default=%s\n", str(vpiDecompile, vpi_handle(vpiExpr, f)));
      }
    printf("spec=%s\n", str(vpiType, vpi_handle(vpiPropertySpec, p)));
  }
  vpiHandle pa = vpi_handle_by_name("top.pa", 0);
  vpiHandle inst = pa ? vpi_handle(vpiProperty, pa) : 0;
  printf("inst type=%s\n", str(vpiType, inst));
  if (!inst)
    return;
  printf("decl=%s\n", str(vpiName, vpi_handle(vpiPropertyDecl, inst)));
  vpiHandle a, args = vpi_iterate(vpiArgument, inst);
  if (args)
    while ((a = vpi_scan(args)))
      printf("arg %s\n", str(vpiDecompile, a));
}
