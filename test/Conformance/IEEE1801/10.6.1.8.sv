// CLAUSE: Supply net
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.8/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_SUPPLY_NET{{$}}
// CHECK: name=vdd{{$}}
// CHECK: parent=/top{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=2{{$}}
// CHECK: scope=/top{{$}}
// CHECK: root=/top/vdd{{$}}
// CHECK: fanin=/top/vdd{{$}}
// CHECK: resolve=UNRESOLVED{{$}}
// CHECK: value=FULL_ON 900000{{$}}

// 1801-2018 10.6.1.8: create_supply_net makes this object, with the values in its example table. It
// takes the same-name port's value through the connection, shown after writing the port.
module top;
import UPF::*;
upfHandleT h;
upfResolveE resolve;
upfSupplyTypeT value;
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
  h = at("/top/vdd@upfSupplyNetT");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $display("scope=%s", link(h, UPF_CREATION_SCOPE));
  $display("root=%s", link(h, UPF_ROOT_DRIVER));
  each("fanin", upf_query_object_properties(h, UPF_FANIN_CONN));
  resolve = upfResolveE'(number(h, UPF_RESOLVE_TYPE));
  $display("resolve=%s", resolve.name());
  void'(supply_on("/top/vdd", 0.9));
  #1;
  value = upf_get_label_upfSupplyTypeT(upf_query_object_properties(h, UPF_CURRENT_VALUE));
  $display("value=%s %0d", value.state.name(), value.voltage);
  $finish;
end
endmodule
