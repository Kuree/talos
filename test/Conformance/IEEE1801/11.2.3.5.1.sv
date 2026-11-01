// CLAUSE: upf_query_object_type
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.5.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: object=UPF_POWER_DOMAIN{{$}}
// CHECK: integer=UPF_INTEGER{{$}}
// CHECK: string=UPF_STRING{{$}}
// CHECK: list=UPF_ITERATOR{{$}}
// CHECK: net=UPF_SUPPLY_NET{{$}}

// 1801-2018 11.2.3.5.1: the class literal of an object or a property handle, including its example's UPF_INTEGER.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT pd;
wire q;
leaf dut(q);
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
initial begin
  pd = upf_get_handle_by_name("/top/PD");
  $display("object=%s", kind(pd));
  $display("integer=%s", kind(upf_query_object_properties(pd, UPF_LINE)));
  $display("string=%s", kind(upf_query_object_properties(pd, UPF_NAME)));
  $display("list=%s", kind(upf_query_object_properties(pd, UPF_SUPPLY_SET_HANDLES)));
  $display("net=%s", kind(upf_get_handle_by_name("/top/VDD")));
  $finish;
end
endmodule
