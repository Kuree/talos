#include "svdpi.h"

extern int observe_index(int expected, int next_index);

int select_row(const svOpenArrayHandle selector) {
  const int *row = svGetArrElemPtr1(selector, 0);
  return row ? *row : -1;
}

void fill_plain(const svOpenArrayHandle rows) {
  int *first = svGetArrElemPtr2(rows, 0, 0);
  if (first)
    *first = 5;
}

int fill(const svOpenArrayHandle rows, int before_call, int after_call) {
  int *first = svGetArrElemPtr2(rows, 0, 0);
  if (!first || !svGetArrElemPtr2(rows, 0, 1) ||
      !observe_index(before_call, after_call))
    return 0;
  *first = 99;
  return 1;
}
