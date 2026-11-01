// CLAUSE: Handle ID or UPF handle
// REQUIRES: upf
// XFAIL: *
// upf_query_object_properties (11.1) and bind_checker (6.12) are not registered UPF commands.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.3.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: path=/top{{$}}
// CHECK: extent=#UPFEXTENT{{[0-9]*}}#{{$}}
// CHECK: UPF_HDL_SCOPE UPF_EXTENT{{$}}

// 1801-2018 10.3.2.1: a UPF handle is either a hierarchical path ID or a tool-generated ID. The Tcl
// strings of both kinds are handed to the HDL side, where each one must find the same object.
module show #(parameter string path = "unset", extent = "unset");
import UPF::*;
upfClassIdE byPath, byId;
initial begin
  $display("path=%s", path);
  $display("extent=%s", extent);
  byPath = upf_query_object_type(upf_get_handle_by_name(path));
  byId = upf_query_object_type(upf_get_handle_by_name(extent));
  $display("%s %s", byPath.name(), byId.name());
end
endmodule
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
wire q;
leaf dut(q);
endmodule
