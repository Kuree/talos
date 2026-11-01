// CLAUSE: PST state
// REQUIRES: upf
// XFAIL: *
// create_pst is not a registered UPF command, and the UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.17/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_PST_STATE{{$}}
// CHECK: name=chip_on{{$}}
// CHECK: parent=/top/chip_pst{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=6{{$}}
// CHECK: scope=/top{{$}}
// CHECK-DAG: supply=/top/vdd.on1V{{$}}
// CHECK-DAG: supply=/top/vdd1.off{{$}}
// CHECK: active=1{{$}}
// CHECK: mismatch=0{{$}}

// 1801-2018 10.6.1.17: add_pst_state makes this object, with the values in its example table. Its dynamic
// upf_is_active is true only while the supplies are in the listed port states.
module top;
import UPF::*;
upfHandleT h;
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
function automatic void each(string key, upfHandleT list);
  for (upfHandleT h = upf_iter_get_next(list); h != upf_null; h = upf_iter_get_next(list))
    $display("%s=%s", key, upf_query_object_pathname(h));
endfunction
initial begin
  h = at("/top/chip_pst.chip_on");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $display("scope=%s", link(h, UPF_CREATION_SCOPE));
  each("supply", upf_query_object_properties(h, UPF_SUPPLY_STATES));
  void'(supply_on("/top/vdd", 1.0));
  #1;
  $display("active=%0d", number(h, UPF_IS_ACTIVE));
  void'(supply_on("/top/vdd1", 1.0));
  #1;
  $display("mismatch=%0d", number(h, UPF_IS_ACTIVE));
  $finish;
end
endmodule
