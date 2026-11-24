#include "sv_vpi_user.h"
#include <stdio.h>

// Prints vpiPacked and vpiTagged for each named object and its typespec.
void probe(void) {
  static const char *names[] = {"top.su", "top.sp", "top.un", "top.ta",
                                "top.sn", "top.tn", "top.so"};
  for (unsigned i = 0; i != sizeof(names) / sizeof(names[0]); ++i) {
    vpiHandle object = vpi_handle_by_name((PLI_BYTE8 *)names[i], NULL);
    vpiHandle type = vpi_handle(vpiTypespec, object);
    // vpi_get_str's buffer is reused by its next call (38.11): print each
    // string before asking for the next one.
    printf("%s %s packed=%d tagged=%d", names[i],
           vpi_get_str(vpiType, object), vpi_get(vpiPacked, object),
           vpi_get(vpiTagged, object));
    printf(" %s packed=%d tagged=%d\n", vpi_get_str(vpiType, type),
           vpi_get(vpiPacked, type), vpi_get(vpiTagged, type));
  }
}

static void printHex(const char *name) {
  s_vpi_value value = {vpiHexStrVal, {0}};
  vpi_get_value(vpi_handle_by_name((PLI_BYTE8 *)name, NULL), &value);
  printf(" %s=%s", name, value.value.str);
}

// IEEE 1800-2023 7.3.1: each member of a soft packed union is right-justified,
// and writing a member leaves the bits above it unchanged.
void soft_layout(void) {
  printf("soft:");
  printHex("top.so");
  printHex("top.so.a");
  printHex("top.so.b");
  s_vpi_value value = {vpiIntVal, {0}};
  value.value.integer = 0xf;
  vpi_put_value(vpi_handle_by_name((PLI_BYTE8 *)"top.so.a", NULL), &value,
                NULL, vpiNoDelay);
  printf("\nafter a=f:");
  printHex("top.so");
  printf("\n");
}
