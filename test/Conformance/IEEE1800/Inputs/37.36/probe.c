#include "sv_vpi_user.h"
#include <ctype.h>
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static const char *bin(vpiHandle h) {
  s_vpi_value v = {.format = vpiBinStrVal};
  vpi_get_value(h, &v);
  return v.value.str ? v.value.str : "null";
}
static void kind(vpiHandle h) {
  printf(" comb=%d seq=%d", vpi_get(vpiPrimType, h) == vpiCombPrim, vpi_get(vpiPrimType, h) == vpiSeqPrim);
}
// The table entry's decompilation, with the spacing removed: 38.15 does not fix the spacing.
static void entry_text(vpiHandle entry) {
  s_vpi_value v = {.format = vpiStringVal};
  vpi_get_value(entry, &v);
  for (const char *c = v.value.str; c && *c; c++)
    if (!isspace((unsigned char)*c))
      putchar(*c);
}
static void report(const char *name) {
  vpiHandle u = vpi_handle_by_name(name, 0);
  printf("udp type=%s", str(vpiType, u));
  printf(" def=%s", str(vpiDefName, u));
  kind(u);
  printf(" value=%s\n", bin(u));

  vpiHandle d = u ? vpi_handle(vpiUdpDefn, u) : 0;
  printf("defn type=%s", str(vpiType, d));
  printf(" def=%s", str(vpiDefName, d));
  if (!d) {
    printf("\n");
    return;
  }
  kind(d);
  printf(" inputs=%d initial=%d\n", vpi_get(vpiSize, d), vpi_handle(vpiInitial, d) != 0);
  vpiHandle x, it = vpi_iterate(vpiIODecl, d);
  if (it)
    while ((x = vpi_scan(it)))
      printf("io %s\n", str(vpiName, x));
  int n = 0;
  it = vpi_iterate(vpiTableEntry, d);
  if (it)
    while ((x = vpi_scan(it))) {
      printf("entry size=%d text=", vpi_get(vpiSize, x));
      entry_text(x);
      printf("\n");
      n++;
    }
  printf("entries=%d\n", n);
}
void probe(void) {
  report("top.ua");
  report("top.uf");
}
