#include "svdpi.h"
#include <stdio.h>

extern int reenter(int *ok);

int check_plain(void) {
  const char *file = "sentinel";
  int line = -1;
  return !svGetScope() && !svGetCallerInfo(&file, &line) && line == -1 &&
         !svGetScopeFromName("dpi_context_reentry");
}

int check_nested(void) {
  svScope scope = svGetScope();
  const char *file;
  int line;
  return scope && scope == svGetScopeFromName("dpi_context_reentry") &&
         svGetCallerInfo(&file, &line) && line > 0;
}

int enter(void) {
  svScope outer = svGetScope();
  int ok = 0;
  int status = reenter(&ok);
  printf("nested=%d restored=%d\n", ok, outer && svGetScope() == outer);
  return status;
}
