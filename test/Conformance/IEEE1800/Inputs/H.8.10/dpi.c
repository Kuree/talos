#include "svdpi.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>
typedef struct { int i; double r; } c35_pair;
int c35_strings(const char **s,const char **out) {
  int ok=strcmp(*s,"before")==0; *s="after"; *out="output"; return ok;
}
