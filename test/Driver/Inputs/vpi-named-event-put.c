#include "sv_vpi_user.h"
#include <stdio.h>

static void report(const char *what) {
  s_vpi_error_info info;
  printf("%s error=%s\n", what,
         vpi_chk_error(&info) && info.message ? info.message : "none");
}

// IEEE 1800-2023 38.34: a put to a named event toggles it, needs no value and
// accepts NULL; any supplied value is ignored.
void put_null(void) {
  vpi_put_value(vpi_handle_by_name("top.e", NULL), NULL, NULL, vpiNoDelay);
  report("null");
}

void put_int(void) {
  s_vpi_value value = {vpiIntVal, {0}};
  value.value.integer = 7;
  vpi_put_value(vpi_handle_by_name("top.e", NULL), &value, NULL, vpiNoDelay);
  report("int");
}

void put_element(void) {
  vpiHandle array = vpi_handle_by_name("top.ea", NULL);
  vpi_put_value(vpi_handle_by_index(array, 1), NULL, NULL, vpiNoDelay);
  report("element");
}

void put_delayed(void) {
  s_vpi_time delay = {vpiSimTime, 0, 1, 0.0};
  vpi_put_value(vpi_handle_by_name("top.e", NULL), NULL, &delay,
                vpiInertialDelay);
  report("delayed");
}
