#include <stdint.h>

extern int c_invalid_disable(int32_t *result);

int drive_invalid_disable(int32_t reenter, int32_t *result) {
  int status = c_invalid_disable(result);
  if (reenter && status == 1) {
    c_invalid_disable(result);
    return 1;
  }
  return status == 1 ? 2 : status;
}
