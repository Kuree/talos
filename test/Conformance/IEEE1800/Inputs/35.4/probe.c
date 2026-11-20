#include "svdpi.h"

int c_named(int x) { return x + 1; }
int c_word(const svLogicVecVal *v) { return (int)v[0].aval; }
int c_time(const svLogicVecVal *v) { return (int)(v[0].aval + v[1].aval); }
int c_signed_time(const svLogicVecVal *v) { return c_time(v); }
int c_packed(const svLogicVecVal *v) { return (int)v[0].aval; }

struct unpacked_pair {
  int words[2];
};
int c_unpacked(const struct unpacked_pair *v) {
  return v->words[0] + v->words[1];
}
