// CLAUSE: Class ID
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.2.5/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: domain=UPF_POWER_DOMAIN{{$}}
// CHECK: strategy=UPF_ISOLATION_STRATEGY{{$}}
// CHECK: scope=UPF_HDL_SCOPE{{$}}
// CHECK: relationship=UPF_EXTENT{{$}}
// CHECK: basic=UPF_STRING{{$}}
// CHECK: compare=1 0{{$}}

// 1801-2018 11.2.2.5 Table 39: HDL identifies classes by upfClassIdE. The literals are read from real objects
// of each group and from a basic property, then compared, so declaring the enum is not enough.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
logic iso = 0;
upfClassIdE c;
wire q;
leaf dut(q);
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
initial begin
  $display("domain=%s", kind(upf_get_handle_by_name("/top/PD")));
  $display("strategy=%s", kind(upf_get_handle_by_name("/top/PD.ISO")));
  $display("scope=%s", kind(upf_get_handle_by_name("/top/dut")));
  $display("relationship=%s", kind(upf_query_object_properties(upf_get_handle_by_name("/top/PD"), UPF_EFFECTIVE_EXTENTS)));
  $display("basic=%s", kind(upf_query_object_properties(upf_get_handle_by_name("/top/PD"), UPF_NAME)));
  c = upf_query_object_type(upf_get_handle_by_name("/top/VDD"));
  $display("compare=%0d %0d", c == UPF_SUPPLY_NET, c == UPF_SUPPLY_PORT);
  $finish;
end
endmodule
