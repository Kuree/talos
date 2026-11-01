#include "sv_vpi_user.h"
#include <stdio.h>
void probe(void) {
  s_vpi_error_info info = {0};
  vpi_get(vpiSize, 0);
  int bad = vpi_chk_error(&info) != 0;
  printf("bad call error=%d level_set=%d message_set=%d\n", bad, info.level != 0, info.message != 0);
  int type = vpi_get(vpiType, vpi_handle_by_name("top.n", 0));
  printf("good call type=%d error=%d\n", type == vpiIntVar, vpi_chk_error(&info) != 0);
}
