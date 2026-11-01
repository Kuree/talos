#include "sv_vpi_user.h"
#include <stdio.h>
static void show_sim(void) {
  s_vpi_time t = {.type = vpiSimTime};
  vpi_get_time(NULL, &t);
  printf("sim high=%u low=%u\n", t.high, t.low);
}
static double scaled(vpiHandle object) {
  s_vpi_time t = {.type = vpiScaledRealTime};
  vpi_get_time(object, &t);
  return t.real;
}
void probe(void) {
  show_sim();
  printf("null scaled=%.2f\n", scaled(NULL));
  printf("top scaled=%.2f\n", scaled(vpi_handle_by_name("top", 0)));
  printf("u scaled=%.2f\n", scaled(vpi_handle_by_name("top.u", 0)));
  // 37.4x: queues come in increasing time order, and the current one can come first.
  s_vpi_time now = {.type = vpiSimTime}, t = {.type = vpiSimTime};
  vpi_get_time(NULL, &now);
  vpiHandle queues = vpi_iterate(vpiTimeQueue, NULL);
  for (vpiHandle q; queues && (q = vpi_scan(queues));) {
    vpi_get_time(q, &t);
    if (t.low != now.low) {
      printf("next queue high=%u low=%u\n", t.high, t.low);
      vpi_release_handle(queues);
      return;
    }
  }
  printf("next queue none\n");
}
void probe_wide(void) { show_sim(); }
