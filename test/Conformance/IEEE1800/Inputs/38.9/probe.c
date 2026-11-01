#include "sv_vpi_user.h"
#include <stdint.h>
#include <stdio.h>
#include <string.h>
static PLI_INT32 restarted(p_cb_data cb) {
  PLI_INT32 id = (PLI_INT32)(intptr_t)cb->user_data;
  char buffer[8] = {0};
  PLI_INT32 n = vpi_get_data(id, buffer, 2);
  printf("chunk n=%d %.2s\n", n, buffer);
  n = vpi_get_data(id, buffer, 5);
  printf("chunk n=%d %.5s\n", n, buffer);
  // More than was stored: what is left, the remaining bytes zero, and the actual count.
  memset(buffer, 'z', sizeof buffer);
  n = vpi_get_data(id, buffer, 3);
  printf("past end n=%d %.1s zero=%d\n", n, buffer, buffer[1] == 0 && buffer[2] == 0);
  return 0;
}
static PLI_INT32 saving(p_cb_data cb) {
  PLI_INT32 id = vpi_get(vpiSaveRestartID, NULL);
  vpi_put_data(id, "abc", 3);
  vpi_put_data(id, "defgh", 5);
  // A restart keeps only restart callbacks, and user_data holds the id, not a pointer.
  s_cb_data restart = {.reason = cbStartOfRestart, .cb_rtn = restarted, .user_data = (PLI_BYTE8 *)(intptr_t)id};
  vpi_register_cb(&restart);
  return 0;
}
static void start(void) {
  s_cb_data save = {.reason = cbStartOfSave, .cb_rtn = saving};
  vpi_register_cb(&save);
}
void (*vlog_startup_routines[])(void) = {start, 0};
