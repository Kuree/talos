// CLAUSE: Power model
// REQUIRES: upf
// XFAIL: *
// define_power_model is not a registered UPF command, and the UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.22/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_POWER_MODEL{{$}}
// CHECK: name=upf_model{{$}}
// CHECK: line=1{{$}}
// CHECK: for={{.*}}leaf{{.*$}}
// CHECK: element=/top/dut{{$}}
// CHECK: extentclass=1{{$}}

// 1801-2018 10.6.1.22: define_power_model makes this object with the rooted handle /<name>. Its extent
// appears when apply_power_model applies it, and links the model to the instance.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
wire q;
leaf dut(q);
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = at("/upf_model");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("line=%0d", number(h, UPF_LINE));
  $display("for=%s", text(h, UPF_FOR_MODELS));
  $display("element=%s", link(upf_query_object_properties(h, UPF_EFFECTIVE_EXTENTS), UPF_HDL_ELEMENT));
  $display("extentclass=%0d", upf_object_in_class(h, UPF_EXTENT_CLASS));
  $finish;
end
endmodule
