#include "sv_vpi_user.h"
#include <stdint.h>
#include <stdio.h>
static PLI_INT32 read_one(p_cb_data cb) {
  char buffer[8] = {0};
  PLI_INT32 n = vpi_get_data((PLI_INT32)(intptr_t)cb->user_data, buffer, 7);
  printf("id one n=%d %s\n", n, buffer);
  return 0;
}
static PLI_INT32 read_two(p_cb_data cb) {
  char buffer[8] = {0};
  PLI_INT32 n = vpi_get_data((PLI_INT32)(intptr_t)cb->user_data, buffer, 2);
  printf("id two n=%d %s\n", n, buffer);
  return 0;
}
static PLI_INT32 saving(p_cb_data cb) {
  // Any number of calls per id, in any order across ids.
  PLI_INT32 one = vpi_get(vpiSaveRestartID, NULL), two = vpi_get(vpiSaveRestartID, NULL);
  int a = vpi_put_data(one, "abc", 3);
  int c = vpi_put_data(two, "xy", 2);
  int b = vpi_put_data(one, "defg", 4);
  // numOfBytes "shall be greater than zero": zero is an error, returned as 0.
  printf("put a=%d b=%d c=%d zero=%d\n", a, b, c, vpi_put_data(one, "x", 0));
  s_cb_data first = {.reason = cbStartOfRestart, .cb_rtn = read_one, .user_data = (PLI_BYTE8 *)(intptr_t)one};
  s_cb_data second = {.reason = cbStartOfRestart, .cb_rtn = read_two, .user_data = (PLI_BYTE8 *)(intptr_t)two};
  vpi_register_cb(&first);
  vpi_register_cb(&second);
  return 0;
}
static void start(void) {
  s_cb_data save = {.reason = cbStartOfSave, .cb_rtn = saving};
  vpi_register_cb(&save);
}
void (*vlog_startup_routines[])(void) = {start, 0};
