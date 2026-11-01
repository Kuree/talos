// CLAUSE: upf_get_value_str
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.2.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: name=PD{{$}}
// CHECK: strategy=ISO{{$}}
// CHECK: file={{.*}}design.upf{{$}}

// 1801-2018 11.2.3.2.2: the string value of a property handle. Different objects and properties give
// different strings, so a constant answer fails.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
logic iso = 0;
upfHandleT pd;
wire q;
leaf dut(q);
initial begin
  pd = upf_get_handle_by_name("/top/PD");
  $display("name=%s", upf_get_value_str(upf_query_object_properties(pd, UPF_NAME)));
  $display("strategy=%s", upf_get_value_str(upf_query_object_properties(upf_get_handle_by_name("/top/PD.ISO"), UPF_NAME)));
  $display("file=%s", upf_get_value_str(upf_query_object_properties(pd, UPF_FILE)));
  $finish;
end
endmodule
