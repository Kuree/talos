#include "svdpi.h"

extern void select_second(void);

int edit(const svOpenArrayHandle values) {
  int *first = svGetArrElemPtr1(values, 0);
  if (!first)
    return -1;
  int original = *first;
  select_second();
  *first = 99;
  return original;
}

void fill(const svOpenArrayHandle values, int *n) {
  int *first = svGetArrElemPtr1(values, 0);
  int *second = svGetArrElemPtr1(values, 1);
  if (first && second) {
    *first = 5;
    *second = 6;
  }
  *n = 7;
}
