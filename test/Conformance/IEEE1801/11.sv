// CLAUSE: Information model application programmable interface (API)
// REQUIRES: upf
// XFAIL: *
// upf_query_object_type, upf_query_object_properties (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: tclClass=upfSupplyNetT{{$}}
// CHECK: tclName=VDD{{$}}
// CHECK: hdlClass=UPF_SUPPLY_NET{{$}}
// CHECK: hdlName=VDD{{$}}

// 1801-2018 11, 11.2.3.5.1 NOTE: the model has a Tcl and an HDL interface, which give one object the class
// name in Tcl and the upfClassIdE literal in HDL, and the same property values.
module show #(parameter string tclClass = "unset", tclName = "unset");
import UPF::*;
upfHandleT h;
upfClassIdE c;
initial begin
  $display("tclClass=%s", tclClass);
  $display("tclName=%s", tclName);
  h = upf_get_handle_by_name("/top/VDD");
  c = upf_query_object_type(h);
  $display("hdlClass=%s", c.name());
  $display("hdlName=%s", upf_get_value_str(upf_query_object_properties(h, UPF_NAME)));
end
endmodule
module top;
endmodule
