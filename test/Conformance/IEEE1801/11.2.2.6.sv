// CLAUSE: Property ID
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.2.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: UPF_NAME=PD{{$}}
// CHECK: UPF_LINE=4{{$}}
// CHECK: UPF_PARENT=/top{{$}}
// CHECK: UPF_CREATION_SCOPE=/top{{$}}

// 1801-2018 11.2.2.6 Table 40: HDL names properties by upfPropertyIdE. Each literal has to select its property
// on a real object, so declaring the enum alone prints nothing that matches.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
upfPropertyIdE id;
wire q;
leaf dut(q);
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = upf_get_handle_by_name("/top/PD");
  id = UPF_NAME;
  $display("%s=%s", id.name(), upf_get_value_str(upf_query_object_properties(h, id)));
  id = UPF_LINE;
  $display("%s=%0d", id.name(), upf_get_value_int(upf_query_object_properties(h, id)));
  id = UPF_PARENT;
  $display("%s=%s", id.name(), link(h, id));
  id = UPF_CREATION_SCOPE;
  $display("%s=%s", id.name(), link(h, id));
  $finish;
end
endmodule
