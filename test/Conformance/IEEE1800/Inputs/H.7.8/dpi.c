#include "svdpi.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>
typedef struct { int i; double r; } c35_pair;
void c35_struct(c35_pair *v) { v->i+=7; v->r*=2; }
