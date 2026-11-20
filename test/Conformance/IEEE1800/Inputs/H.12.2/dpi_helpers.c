#include "svdpi.h"

int bounds(const svOpenArrayHandle q, int n) {
  return svDimensions(q) == 1 && svSize(q, 0) == 32 && svLeft(q, 1) == 0 &&
         svRight(q, 1) == n - 1 && svLow(q, 1) == 0 && svHigh(q, 1) == n - 1 &&
         svIncrement(q, 1) == -1 && svSize(q, 1) == n;
}
