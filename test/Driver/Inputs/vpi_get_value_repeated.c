#include "vpi_user.h"
#include <stdio.h>

// IEEE 1800-2023 38.15: every vpi_get_value reports the object's current
// value. The same handles are read at several times, in every format, and
// again right after vpi_put_value writes, forces and releases.
static const char *names[] = {"top.r",  "top.s",  "top.w",  "top.b",
                              "top.q",  "top.p",  "top.e",  "top.sb",
                              "top.tm", "top.pn", "top.cnt", "top.wide"};
#define COUNT (sizeof(names) / sizeof(*names))
static vpiHandle handles[COUNT];

static void show(vpiHandle handle, const char *name) {
  s_vpi_value value = {.format = vpiIntVal};
  vpi_get_value(handle, &value);
  printf("%s int=%d", name, (int)value.value.integer);
  static const PLI_INT32 strings[] = {vpiBinStrVal, vpiOctStrVal, vpiHexStrVal,
                                      vpiDecStrVal};
  static const char *labels[] = {"bin", "oct", "hex", "dec"};
  for (unsigned i = 0; i != 4; ++i) {
    value.format = strings[i];
    vpi_get_value(handle, &value);
    printf(" %s=%s", labels[i], value.value.str);
  }
  // vpiStringVal bytes, printed in hexadecimal.
  value.format = vpiStringVal;
  vpi_get_value(handle, &value);
  printf(" str=");
  for (const char *c = value.value.str; *c; ++c)
    printf("%02x", (unsigned)(unsigned char)*c);
  value.format = vpiVectorVal;
  vpi_get_value(handle, &value);
  printf(" vec=%08x/%08x", (unsigned)value.value.vector[0].aval,
         (unsigned)value.value.vector[0].bval);
  value.format = vpiScalarVal;
  vpi_get_value(handle, &value);
  printf(" scalar=%d", (int)value.value.scalar);
  value.format = vpiTimeVal;
  vpi_get_value(handle, &value);
  printf(" time=%u", (unsigned)value.value.time->low);
  value.format = vpiStrengthVal;
  vpi_get_value(handle, &value);
  printf(" strength=%d/%d/%d", (int)value.value.strength[0].logic,
         (int)value.value.strength[0].s0, (int)value.value.strength[0].s1);
  value.format = vpiObjTypeVal;
  vpi_get_value(handle, &value);
  printf(" objtype=%d\n", (int)value.format);
}

static void put(vpiHandle handle, int integer, PLI_INT32 flags) {
  s_vpi_value value = {.format = vpiIntVal};
  value.value.integer = integer;
  vpi_put_value(handle, &value, NULL, flags);
}

void probe(int phase) {
  s_vpi_time now = {.type = vpiSimTime};
  vpi_get_time(NULL, &now);
  printf("t=%u\n", (unsigned)now.low);
  for (unsigned i = 0; i != COUNT; ++i) {
    if (!handles[i])
      handles[i] = vpi_handle_by_name((PLI_BYTE8 *)names[i], NULL);
    show(handles[i], names[i]);
  }
  if (phase != 1)
    return;
  put(handles[0], 0x11, vpiNoDelay);
  show(handles[0], "deposit top.r");
  put(handles[10], 0x40, vpiForceFlag);
  show(handles[10], "force top.cnt");
  put(handles[10], 0, vpiReleaseFlag);
  show(handles[10], "release top.cnt");
}
