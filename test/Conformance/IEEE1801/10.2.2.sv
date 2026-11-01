// CLAUSE: Objects
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.2.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: UPF_POWER_DOMAIN UPF_HDL_SCOPE UPF_EXTENT{{$}}
// CHECK: unique=1{{$}}
// CHECK: access=PD{{$}}

// 1801-2018 10.2.2: each object of the three groups is denoted by a unique UPF handle, and the APIs
// use that handle to reach the information on it.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT domain, scope, extent;
wire q;
leaf dut(q);
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
initial begin
  domain = upf_get_handle_by_name("/top/PD");
  scope = upf_get_handle_by_name("/top/dut");
  extent = upf_query_object_properties(domain, UPF_EFFECTIVE_EXTENTS);
  $display("%s %s %s", kind(domain), kind(scope), kind(extent));
  $display("unique=%0d", domain != upf_null && scope != upf_null && extent != upf_null &&
                         domain != scope && scope != extent && domain != extent);
  $display("access=%s", text(domain, UPF_NAME));
  $finish;
end
endmodule
