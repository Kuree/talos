// CLAUSE: upf_object_in_class
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.5.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: own=1{{$}}
// CHECK: base=1{{$}}
// CHECK: other=0{{$}}
// CHECK: hdl=0{{$}}
// CHECK: integer=1{{$}}

// 1801-2018 11.2.3.5.2: 1 when the object belongs to the class, including a base class or a property's
// basic class, and 0 otherwise.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT pd;
wire q;
leaf dut(q);
initial begin
  pd = upf_get_handle_by_name("/top/PD");
  $display("own=%0d", upf_object_in_class(pd, UPF_POWER_DOMAIN));
  $display("base=%0d", upf_object_in_class(pd, UPF_BASE_UPF));
  $display("other=%0d", upf_object_in_class(pd, UPF_SUPPLY_NET));
  $display("hdl=%0d", upf_object_in_class(pd, UPF_BASE_HDL));
  $display("integer=%0d", upf_object_in_class(upf_query_object_properties(pd, UPF_LINE), UPF_INTEGER));
  $finish;
end
endmodule
