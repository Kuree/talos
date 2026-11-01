#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static void args(vpiHandle call) {
  vpiHandle a, it = vpi_iterate(vpiArgument, call);
  if (!it)
    return;
  while ((a = vpi_scan(it))) {
    int type = vpi_get(vpiType, a);
    if (type == vpiOperation && vpi_get(vpiOpType, a) == vpiNullOp) {
      printf("arg null operation\n");
    } else if (type == vpiConstant && vpi_get(vpiConstType, a) == vpiStringConst) {
      s_vpi_value v = {.format = vpiStringVal};
      vpi_get_value(a, &v);
      printf("arg string constant %s\n", v.value.str);
    } else {
      s_vpi_value v = {.format = vpiIntVal};
      vpi_get_value(a, &v);
      printf("arg %s value=%d\n", str(vpiType, a), v.value.integer);
    }
  }
}
static void report(vpiHandle call) {
  int type = vpi_get(vpiType, call);
  printf("call=%s", str(vpiType, call));
  printf(" name=%s", str(vpiName, call));
  if (type == vpiSysTaskCall || type == vpiSysFuncCall)
    printf(" user=%d", vpi_get(vpiUserDefn, call));
  printf("\n");
  if (type == vpiMethodFuncCall || type == vpiMethodTaskCall)
    printf("prefix=%s\n", str(vpiName, vpi_handle(vpiPrefix, call)));
  if (type == vpiFuncCall || type == vpiMethodFuncCall || type == vpiTaskCall || type == vpiMethodTaskCall) {
    vpiHandle target = vpi_handle(type == vpiFuncCall || type == vpiMethodFuncCall ? vpiFunction : vpiTask, call);
    printf("target=%s", str(vpiType, target));
    printf(" name=%s\n", str(vpiName, target));
  }
  args(call);
}
void probe(void) {
  vpiHandle procs = vpi_iterate(vpiProcess, vpi_handle_by_name("top", 0));
  vpiHandle init = procs ? vpi_scan(procs) : 0;
  vpiHandle body = init ? vpi_handle(vpiStmt, init) : 0;
  vpiHandle s, it = body ? vpi_iterate(vpiStmt, body) : 0;
  if (!it) {
    printf("no statements\n");
    return;
  }
  while ((s = vpi_scan(it)))
    report(vpi_get(vpiType, s) == vpiAssignment ? vpi_handle(vpiRhs, s) : s);
}
