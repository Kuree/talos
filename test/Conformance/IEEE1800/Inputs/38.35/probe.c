#include "sv_vpi_user.h"
#include <stdio.h>
void probe(void) {
  PLI_INT32 from[1] = {1};
  PLI_INT32 values[2] = {7, 8};
  s_vpi_arrayvalue v = {.format = vpiIntVal, .value.integers = values};
  vpi_put_value_array(vpi_handle_by_name("top.a", 0), &v, from, 2);

  // vpiOneValue applies one element's data to the whole section.
  PLI_INT32 one = 9;
  from[0] = 0;
  s_vpi_arrayvalue o = {.format = vpiIntVal, .flags = vpiOneValue, .value.integers = &one};
  vpi_put_value_array(vpi_handle_by_name("top.b", 0), &o, from, 3);

  // The clause's example order: from a[1][4] it sets a[1][4], a[1][5], a[0][3], a[0][4].
  unsigned char raw[4 * 2 * 2] = {0x45, 0x01, 0, 0, 0x56, 0x01, 0, 0, 0x03, 0x02, 0, 0, 0x04, 0x0f, 0, 0x0f};
  PLI_INT32 at[2] = {1, 4};
  s_vpi_arrayvalue r = {.format = vpiRawFourStateVal, .value.rawvals = (PLI_BYTE8 *)raw};
  vpi_put_value_array(vpi_handle_by_name("top.m", 0), &r, at, 4);
}
void bad_flags(void) {
  // "Flags other than vpiPropagateOff, vpiOneValue, or vpiNoDelay ... shall be an error."
  PLI_INT32 from[1] = {0}, value = 5;
  s_vpi_arrayvalue v = {.format = vpiIntVal, .flags = vpiUserAllocFlag, .value.integers = &value};
  vpi_put_value_array(vpi_handle_by_name("top.a", 0), &v, from, 1);
  printf("bad flags error=%d\n", vpi_chk_error(NULL) != 0);
}
