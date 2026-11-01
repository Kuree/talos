#include "sv_vpi_user.h"
#include <stdio.h>
void probe(void) {
  vpiHandle a = vpi_handle_by_name("top.a", 0);
  PLI_INT32 from[1] = {1};
  s_vpi_arrayvalue v = {.format = vpiIntVal};
  vpi_get_value_array(a, &v, from, 2);
  if (!v.value.integers) { printf("vpi allocated: null\n"); return; }
  printf("vpi allocated: %d %d\n", v.value.integers[0], v.value.integers[1]);

  PLI_INT32 mine[2] = {0, 0};
  from[0] = 2;
  s_vpi_arrayvalue u = {.format = vpiIntVal, .flags = vpiUserAllocFlag, .value.integers = mine};
  vpi_get_value_array(a, &u, from, 2);
  printf("user allocated: %d %d pointer_kept=%d\n", mine[0], mine[1], u.value.integers == mine);

  // The clause's example: a[2:0][3:5] from a[1][4] reads a[1][4], a[1][5], a[0][3], a[0][4], a[0][5].
  vpiHandle m = vpi_handle_by_name("top.m", 0);
  PLI_INT32 at[2] = {1, 4};
  PLI_BYTE8 raw[5 * 2 * 2];
  s_vpi_arrayvalue r = {.format = vpiRawFourStateVal, .flags = vpiUserAllocFlag, .value.rawvals = raw};
  vpi_get_value_array(m, &r, at, 5);
  printf("raw:");
  for (int i = 0; i < 5; i++) {
    const unsigned char *e = (const unsigned char *)raw + i * 4;
    printf(" %03x/%03x", e[0] | e[1] << 8, e[2] | e[3] << 8);
  }
  printf("\n");

  s_vpi_arrayvalue w = {.format = vpiVectorVal};
  vpi_get_value_array(m, &w, at, 2);
  if (!w.value.vectors) { printf("vector: null\n"); return; }
  printf("vector: %03x/%03x %03x/%03x\n", w.value.vectors[0].aval, w.value.vectors[0].bval,
         w.value.vectors[1].aval, w.value.vectors[1].bval);

  // vpiShortIntVal "is appropriate only for arrays of vpiShortIntVar or vpiByteVar elements".
  PLI_INT16 shorts[2];
  from[0] = 0;
  s_vpi_arrayvalue bad = {.format = vpiShortIntVal, .flags = vpiUserAllocFlag, .value.shortints = shorts};
  vpi_get_value_array(a, &bad, from, 2);
  printf("inconsistent format: pointer=%s error=%d\n", bad.value.shortints ? "kept" : "null",
         vpi_chk_error(NULL) != 0);
}
