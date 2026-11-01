#include "sv_vpi_user.h"
#include <stdio.h>
#include <string.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static vpiHandle defn(const char *name) {
  vpiHandle d, it = vpi_iterate(vpiClassDefn, vpi_handle_by_name("top", 0));
  if (it)
    while ((d = vpi_scan(it)))
      if (!strcmp(str(vpiName, d), name))
        return d;
  return 0;
}
static int names(const char *label, PLI_INT32 relation, vpiHandle h) {
  int n = 0;
  vpiHandle x, it = vpi_iterate(relation, h);
  if (it)
    while ((x = vpi_scan(it))) {
      printf("%s %s\n", label, str(vpiName, x));
      n++;
    }
  return n;
}
static void header(vpiHandle d) {
  printf("type=%s", str(vpiType, d));
  printf(" name=%s virtual=%d\n", str(vpiName, d), d ? vpi_get(vpiVirtual, d) : -1);
}
void probe(void) {
  vpiHandle base = defn("Base"), derived = defn("Derived");
  header(base);
  header(derived);
  names("var", vpiVariables, derived);
  names("method", vpiMethods, derived);
  printf("base methods=%d\n", names("base method", vpiMethods, base));
  printf("derived classes=%d\n", names("derived", vpiDerivedClasses, base));
  vpiHandle ext = derived ? vpi_handle(vpiExtends, derived) : 0;
  vpiHandle ts = ext ? vpi_handle(vpiClassTypespec, ext) : 0;
  printf("extends=%s\n", str(vpiName, ts ? vpi_handle(vpiClassDefn, ts) : 0));
}
