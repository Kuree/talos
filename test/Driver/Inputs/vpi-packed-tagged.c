#include "sv_vpi_user.h"
#include <stdio.h>

// Prints vpiPacked and vpiTagged for each named object and its typespec.
void probe(void) {
  static const char *names[] = {"top.su", "top.sp", "top.un", "top.ta",
                                "top.sn", "top.tn"};
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
