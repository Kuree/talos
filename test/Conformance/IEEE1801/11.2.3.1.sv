// CLAUSE: Accessing objects and properties
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: relative=ISO{{$}}
// CHECK: parent=/top/dut/PD{{$}}
// CHECK: listed=1{{$}}
// CHECK: end=0{{$}}

// 1801-2018 11.2.3.1: from a name to an object, from a property to an object, and through a list back to
// the first object, whose handle has to compare equal (11.2.2.1 NOTE 2).
module inner(output logic [1:0] q);
  assign q = 2'b01;
endmodule
module leaf(output wire [1:0] q);
  logic iso = 0;
  inner mid(q);
endmodule
module top;
import UPF::*;
wire [1:0] q;
leaf dut(q);
upfHandleT scope, strategy, domain, list;
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
initial begin
  scope = upf_get_handle_by_name("/top/dut");
  strategy = upf_get_handle_by_name("PD.ISO", scope);
  $display("relative=%s", text(strategy, UPF_NAME));
  domain = upf_query_object_properties(strategy, UPF_PARENT);
  $display("parent=%s", upf_query_object_pathname(domain));
  list = upf_query_object_properties(domain, UPF_ISOLATION_STRATEGIES);
  $display("listed=%0d", upf_iter_get_next(list) == strategy);
  $display("end=%0d", upf_iter_get_next(list));
  $finish;
end
endmodule
