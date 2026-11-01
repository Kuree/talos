// CLAUSE: upf_get_value_int
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.2.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: line=4{{$}}
// CHECK: strategyline=5{{$}}
// CHECK: enum=PARENT{{$}}
// CHECK: boolean=0{{$}}

// 1801-2018 11.2.3.2.3, 11.2.2.4: the integer form of integer, Boolean and enumerated properties. An
// enumeration comes back as its position, converted to its literal before use.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
logic iso = 0;
upfHandleT h;
upfLocationE where;
wire q;
leaf dut(q);
initial begin
  h = upf_get_handle_by_name("/top/PD");
  $display("line=%0d", upf_get_value_int(upf_query_object_properties(h, UPF_LINE)));
  h = upf_get_handle_by_name("/top/PD.ISO");
  $display("strategyline=%0d", upf_get_value_int(upf_query_object_properties(h, UPF_LINE)));
  where = upfLocationE'(upf_get_value_int(upf_query_object_properties(h, UPF_LOCATION)));
  $display("enum=%s", where.name());
  $display("boolean=%0d", upf_get_value_int(upf_query_object_properties(h, UPF_IS_NO_ISOLATION)));
  $finish;
end
endmodule
