#include "svdpi.h"
static int calls;
char r_byte(void) { return -5; }
short r_shortint(void) { return -300; }
int r_int(void) { return 70000; }
long long r_longint(void) { return 1LL << 40; }
double r_real(void) { return 2.5; }
float r_shortreal(void) { return 0.25f; }
void *r_chandle(void) { return &calls; }
const char *r_string(void) { return "hello"; }
svBit r_bit(void) { return 1; }
svLogic r_logic(void) { return sv_x; }
void r_void(void) { calls++; }
int r_calls(void) { return calls; }
