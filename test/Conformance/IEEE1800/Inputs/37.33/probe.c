#include "sv_vpi_user.h"
#include <stdio.h>
static const char *str(PLI_INT32 prop, vpiHandle h) {
  const char *s = h ? vpi_get_str(prop, h) : 0;
  return s ? s : "null";
}
static int value(vpiHandle h) {
  s_vpi_value v = {.format = vpiIntVal};
  if (!h)
    return -1;
  vpi_get_value(h, &v);
  return v.value.integer;
}
static const char *defn_name(vpiHandle h) {
  vpiHandle ts = h ? vpi_handle(vpiClassTypespec, h) : 0;
  return str(vpiName, ts ? vpi_handle(vpiClassDefn, ts) : 0);
}
void probe_null(void) {
  vpiHandle p = vpi_handle_by_name("top.p", 0);
  printf("null var id=%lld", (long long)vpi_get64(vpiObjId, p));
  printf(" obj=%s\n", str(vpiType, vpi_handle(vpiClassObj, p)));
}
void probe_live(void) {
  vpiHandle l = vpi_handle_by_name("top.l", 0), p = vpi_handle_by_name("top.p", 0);
  vpiHandle other = vpi_handle_by_name("top.other", 0);
  vpiHandle lo = vpi_handle(vpiClassObj, l), po = vpi_handle(vpiClassObj, p);
  vpiHandle oo = vpi_handle(vpiClassObj, other);
  long long lid = vpi_get64(vpiObjId, l), pid = vpi_get64(vpiObjId, p), oid = vpi_get64(vpiObjId, other);
  printf("obj type=%s\n", str(vpiType, po));
  printf("nonzero=%d alias=%d distinct=%d obj_id_matches=%d\n", lid != 0, lid == pid, lid != oid,
         po && vpi_get64(vpiObjId, po) == pid);
  printf("compare same=%d other=%d\n", vpi_compare_objects(lo, po), vpi_compare_objects(lo, oo));
  printf("declared=%s\n", defn_name(p));
  printf("allocated=%s\n", defn_name(po));
  printf("p.Id=%d\n", value(vpi_handle_by_name("top.p.Id", 0)));
  printf("other.Id=%d\n", value(vpi_handle_by_name("top.other.Id", 0)));
}
