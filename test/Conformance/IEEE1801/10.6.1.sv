// CLAUSE: UPF objects
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: domain=UPF_POWER_DOMAIN{{$}}
// CHECK: strategy=UPF_ISOLATION_STRATEGY{{$}}
// CHECK: set=UPF_SUPPLY_SET{{$}}
// CHECK: ref=UPF_NAMED_REF{{$}}
// CHECK: net=UPF_SUPPLY_NET{{$}}
// CHECK: port=UPF_SUPPLY_PORT{{$}}
// CHECK: upf=1 0{{$}}

// 1801-2018 10.6.1: each UPF command creates an object of its class. A sample of the commonest ones,
// with the UPF group's base class confirmed on one of them.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
logic iso = 0;
wire q;
leaf dut(q);
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
initial begin
  $display("domain=%s", kind(at("/top/PD")));
  $display("strategy=%s", kind(at("/top/PD.ISO")));
  $display("set=%s", kind(at("/top/CORE")));
  $display("ref=%s", kind(at("/top/CORE.power")));
  $display("net=%s", kind(at("/top/VDD")));
  $display("port=%s", kind(at("/top/PAD")));
  h = at("/top/PD.ISO");
  $display("upf=%0d %0d", upf_object_in_class(h, UPF_BASE_UPF), upf_object_in_class(h, UPF_BASE_HDL));
  $finish;
end
endmodule
