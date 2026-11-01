// CLAUSE: Composite domain
// REQUIRES: upf
// XFAIL: *
// create_composite_domain is not a registered UPF command, and the UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.20/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_COMPOSITE_DOMAIN{{$}}
// CHECK: name=CD{{$}}
// CHECK: parent=/top{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=6{{$}}
// CHECK: scope=/top{{$}}
// CHECK-DAG: sub=/top/PD1{{$}}
// CHECK-DAG: sub=/top/PD2{{$}}
// CHECK: handle=/top/CD.primary{{$}}
// CHECK: extentclass=0{{$}}

// 1801-2018 10.6.1.20: create_composite_domain makes this object, with the values in its example table.
// Its class membership has no upfExtentClassT, unlike an ordinary domain's.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
wire a, b;
leaf u1(a), u2(b);
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
  h = at("/top/CD");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $display("scope=%s", link(h, UPF_CREATION_SCOPE));
  each("sub", upf_query_object_properties(h, UPF_SUBDOMAINS));
  each("handle", upf_query_object_properties(h, UPF_SUPPLY_SET_HANDLES));
  $display("extentclass=%0d", upf_object_in_class(h, UPF_EXTENT_CLASS));
  $finish;
end
endmodule
