#include "sv_vpi_user.h"
#include <stdio.h>
#include <string.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  vpi_get_value(h, &v);
  return v.value.integer;
}
static void params(const char *label, vpiHandle ts) {
  vpiHandle p, it = ts ? vpi_iterate(vpiParameter, ts) : 0;
  if (it)
    while ((p = vpi_scan(it))) {
      printf("%s %s", label, str(vpiName, p));
      printf("=%d local=%d\n", value(p), vpi_get(vpiLocalParam, p));
    }
}
static void names(const char *label, PLI_INT32 relation, vpiHandle h) {
  vpiHandle x, it = h ? vpi_iterate(relation, h) : 0;
  if (it)
    while ((x = vpi_scan(it)))
      printf("%s %s\n", label, str(vpiName, x));
}
void probe(void) {
  vpiHandle ts = vpi_handle(vpiClassTypespec, vpi_handle_by_name("top.v", 0));
  vpiHandle defn = ts ? vpi_handle(vpiClassDefn, ts) : 0;
  printf("type=%s", str(vpiType, ts));
  printf(" named=%d user=%d", ts && strlen(str(vpiName, ts)) > 0,
         ts && vpi_get(vpiClassType, ts) == vpiUserDefinedClass);
  printf(" defn=%s\n", str(vpiName, defn));
  params("param", ts);
  names("var", vpiVariables, ts);
  names("method", vpiMethods, ts);
  names("constraint", vpiConstraint, ts);

  vpiHandle base = ts ? vpi_handle(vpiExtends, ts) : 0;
  printf("base defn=%s\n", str(vpiName, base ? vpi_handle(vpiClassDefn, base) : 0));
  params("base param", base);

  vpiHandle mb = vpi_handle(vpiClassTypespec, vpi_handle_by_name("top.mb", 0));
  printf("mailbox mailbox=%d", mb && vpi_get(vpiClassType, mb) == vpiMailboxClass);
  printf(" defn=%s\n", str(vpiName, mb ? vpi_handle(vpiClassDefn, mb) : 0));

  // Detail 10: the class specializations derived directly from a class defn.
  int n = 0;
  vpiHandle s, it = defn ? vpi_iterate(vpiClassTypespec, defn) : 0;
  if (it)
    while ((s = vpi_scan(it))) {
      params("specialization", s);
      n++;
    }
  printf("specializations=%d\n", n);
}
