// CLAUSE: upf_query_object_properties
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.3.1.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: name=PD{{$}}
// CHECK: scope=/top/dut{{$}}
// CHECK: iso=ISO{{$}}
// CHECK: dynamic=1{{$}}

// 1801-2018 11.2.3.1.2: a query returns a handle to a basic value, to an object, to a list iterator or to a
// dynamic property. One case of each, following the clause's examples 1 to 4.
module inner(output logic [1:0] q);
  assign q = 2'b01;
endmodule
module leaf(output wire [1:0] q);
  logic iso = 0;
  inner mid(q);
endmodule
module top;
import UPF::*;
wire [1:0] q;
leaf dut(q);
upfHandleT pd, first, value;
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  pd = upf_get_handle_by_name("/top/dut/PD");
  $display("name=%s", upf_get_value_str(upf_query_object_properties(pd, UPF_NAME)));
  $display("scope=%s", link(pd, UPF_CREATION_SCOPE));
  first = upf_iter_get_next(upf_query_object_properties(pd, UPF_ISOLATION_STRATEGIES));
  $display("iso=%s", upf_get_value_str(upf_query_object_properties(first, UPF_NAME)));
  value = upf_query_object_properties(upf_get_handle_by_name("/top/dut/VDD"), UPF_CURRENT_VALUE);
  $display("dynamic=%0d", upf_object_in_class(value, UPF_SUPPLY_TYPE));
  $finish;
end
endmodule
