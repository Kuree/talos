// CLAUSE: Implemented UPF objects
// REQUIRES: upf
// XFAIL: *
// UPF execution fails: HDL supply-object reuse is not implemented (8.3.4), and the UPF package has no information-model API.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.3.2.2.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: search=UPF_SUPPLY_NET{{$}}
// CHECK: hdl=1 /top/rail{{$}}
// CHECK: rail=FULL_ON 800000{{$}}

// 1801-2018 10.3.2.2.2, 10.6.1.8: an implemented UPF object shares its name with an HDL object. A search
// by name returns the UPF object, a property links it to the HDL object, and the HDL object carries its value.
module top;
import UPF::*;
supply_net_type rail;
upfHandleT net;
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  net = upf_get_handle_by_name("/top/rail");
  $display("search=%s", kind(net));
  $display("hdl=%0d %s", upf_object_in_class(upf_query_object_properties(net, UPF_HDL_IMPLEMENTATION), UPF_HDL_DECL),
           link(net, UPF_HDL_IMPLEMENTATION));
  void'(supply_on("/top/rail", 0.8));
  #1;
  $display("rail=%s %0d", rail.state.name(), rail.voltage);
  $finish;
end
endmodule
