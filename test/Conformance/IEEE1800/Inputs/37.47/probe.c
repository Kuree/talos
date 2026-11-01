#include "sv_vpi_user.h"
#include <stdio.h>
#include <string.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static const char *bin(vpiHandle h) {
  s_vpi_value v = {.format = vpiBinStrVal};
  vpi_get_value(h, &v);
  return v.value.str ? v.value.str : "null";
}
// 5.6.1: the escaped spelling \a (with its terminating space) names the same identifier as a.
static void plain(const char *s) {
  for (; *s; s++) {
    if (*s != '\\') {
      putchar(*s);
      continue;
    }
    while (*++s && *s != ' ')
      putchar(*s);
    if (!*s)
      break;
  }
}
static vpiHandle assignment(const char *lhs) {
  vpiHandle c, it = vpi_iterate(vpiContAssign, vpi_handle_by_name("top", 0));
  if (it)
    while ((c = vpi_scan(it)))
      if (!strcmp(str(vpiName, vpi_handle(vpiLhs, c)), lhs))
        return c;
  return 0;
}
static void report(vpiHandle c) {
  printf("lhs=%s rhs=", str(vpiName, vpi_handle(vpiLhs, c)));
  plain(str(vpiDecompile, vpi_handle(vpiRhs, c)));
  printf(" decl=%d strong0=%d pull1=%d", vpi_get(vpiNetDeclAssign, c), vpi_get(vpiStrength0, c) == vpiStrongDrive,
         vpi_get(vpiStrength1, c) == vpiPullDrive);
  s_vpi_time t[1] = {{.type = vpiScaledRealTime}};
  s_vpi_delay d = {.da = t, .no_of_delays = 1, .time_type = vpiScaledRealTime};
  vpi_get_delays(c, &d);
  printf(" delay=%g", t[0].real);
  vpiHandle expr = vpi_handle(vpiDelay, c);
  if (expr) {
    s_vpi_value v = {.format = vpiIntVal};
    vpi_get_value(expr, &v);
    printf(" vpiDelay=%d\n", v.value.integer);
  } else {
    printf(" vpiDelay=none\n");
  }
}
void describe(void) {
  vpiHandle c, it = vpi_iterate(vpiContAssign, vpi_handle_by_name("top", 0));
  if (it)
    while ((c = vpi_scan(it)))
      report(c);
  vpiHandle b, bits = vpi_iterate(vpiBit, assignment("v"));
  if (bits)
    while ((b = vpi_scan(bits))) {
      printf("bit type=%s", str(vpiType, b));
      printf(" offset=%d size=%d\n", vpi_get(vpiOffset, b), vpi_get(vpiSize, b));
    }
}
void values(int t) {
  printf("t=%d", t);
  printf(" w=%s", bin(vpi_handle_by_name("top.w", 0)));
  printf(" value=%s\n", bin(assignment("w")));
  if (t < 4)
    return;
  vpiHandle b, bits = vpi_iterate(vpiBit, assignment("v"));
  if (bits)
    while ((b = vpi_scan(bits))) {
      printf("bit offset=%d", vpi_get(vpiOffset, b));
      printf(" value=%s\n", bin(b));
    }
}
