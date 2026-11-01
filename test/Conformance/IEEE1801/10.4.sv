// CLAUSE: Classification of objects
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: domain=1 0 0{{$}}
// CHECK: scope=0 1 0{{$}}
// CHECK: extent=0 0 1{{$}}

// 1801-2018 10.4.1: objects are classified into UPF, HDL and relationship groups. Each sample belongs to
// exactly one group's base class (10.4.5), so a class check that always answers the same value fails.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT domain;
wire q;
leaf dut(q);
function automatic void groups(string key, upfHandleT o);
  $display("%s=%0d %0d %0d", key, upf_object_in_class(o, UPF_BASE_UPF), upf_object_in_class(o, UPF_BASE_HDL),
           upf_object_in_class(o, UPF_BASE_RELATIONSHIP));
endfunction
initial begin
  domain = upf_get_handle_by_name("/top/PD");
  groups("domain", domain);
  groups("scope", upf_get_handle_by_name("/top/dut"));
  groups("extent", upf_query_object_properties(domain, UPF_EFFECTIVE_EXTENTS));
  $finish;
end
endmodule
