#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static vpiHandle by_name(const char *name) { return vpi_handle_by_name(name, 0); }
static void head(const char *label, vpiHandle h) {
  printf("%s type=%s", label, str(vpiType, h));
  printf(" full=%s", str(vpiFullName, h));
  printf(" automatic=%d", vpi_get(vpiAutomatic, h));
}
static void shape(vpiHandle h) {
  printf(" size=%d signed=%d method=%d public=%d", vpi_get(vpiSize, h), vpi_get(vpiSigned, h), vpi_get(vpiMethod, h),
         vpi_get(vpiVisibility, h) == vpiPublicVis);
}
static void ret(vpiHandle h) {
  vpiHandle r = vpi_handle(vpiReturn, h);
  printf("return type=%s", str(vpiType, r));
  printf(" name=%s size=%d\n", str(vpiName, r), r ? vpi_get(vpiSize, r) : -1);
}
static void ios(vpiHandle h) {
  vpiHandle x, it = vpi_iterate(vpiIODecl, h);
  if (it)
    while ((x = vpi_scan(it))) {
      printf("io %s input=%d", str(vpiName, x), vpi_get(vpiDirection, x) == vpiInput);
      if (vpi_get(vpiDirection, x) == vpiOutput)
        printf(" input=0 output=1");
      printf("\n");
    }
}
static void dpi(const char *name) {
  vpiHandle h = by_name(name);
  printf("%s import=%d export=%d", str(vpiName, h), vpi_get(vpiAccessType, h) == vpiDPIImportAcc,
         vpi_get(vpiAccessType, h) == vpiDPIExportAcc);
  if (vpi_get(vpiAccessType, h) == vpiDPIImportAcc) {
    printf(" context=%d pure=%d dpic=%d", vpi_get(vpiDPIContext, h), vpi_get(vpiDPIPure, h), vpi_get(vpiDPICStr, h) == vpiDPIC);
    printf(" identifier=%s", str(vpiDPICIdentifier, h));
  }
  printf("\n");
}
void probe(void) {
  vpiHandle h = by_name("top.f8");
  head("f8", h);
  shape(h);
  printf(" sized=%d\n", vpi_get(vpiFuncType, h) == vpiSizedFunc);
  ret(h);
  ios(h);

  h = by_name("top.fi");
  head("fi", h);
  shape(h);
  printf(" int=%d\n", vpi_get(vpiFuncType, h) == vpiIntFunc);
  ret(h);

  h = by_name("top.fr");
  head("fr", h);
  printf(" real=%d\n", vpi_get(vpiFuncType, h) == vpiRealFunc);

  h = by_name("top.fv");
  printf("fv type=%s size=%d\n", str(vpiType, h), vpi_get(vpiSize, h));

  h = by_name("top.tk");
  head("tk", h);
  printf("\n");
  ios(h);
  h = by_name("top.ts");
  head("ts", h);
  printf("\n");

  vpiHandle defn = 0, d, it = vpi_iterate(vpiClassDefn, by_name("top"));
  if (it)
    while ((d = vpi_scan(it)))
      defn = d;
  vpiHandle m, methods = defn ? vpi_iterate(vpiMethods, defn) : 0;
  if (methods)
    while ((m = vpi_scan(methods))) {
      int vis = vpi_get(vpiVisibility, m);
      printf("method full=%s is_method=%d local=%d protected=%d public=%d\n", str(vpiFullName, m), vpi_get(vpiMethod, m),
             vis == vpiLocalVis, vis == vpiProtectedVis, vis == vpiPublicVis);
    }
  dpi("top.probe");
  dpi("top.twice");
  dpi("top.fi");
}
