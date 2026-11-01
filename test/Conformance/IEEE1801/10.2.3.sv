// CLAUSE: Properties
// REQUIRES: upf
// XFAIL: *
// add_supply_state is not a registered UPF command, and the UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.2.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: string=UPF_STRING VDD{{$}}
// CHECK: integer=UPF_INTEGER 1{{$}}
// CHECK: boolean=UPF_BOOLEAN 1{{$}}
// CHECK: float=UPF_REAL 1.000000{{$}}
// CHECK: enumerated=UPF_DIR_IN{{$}}
// CHECK: handle=UPF_HDL_SCOPE /top{{$}}
// CHECK: list=UPF_ITERATOR{{$}}

// 1801-2018 10.2.3.1 Table 13: properties are strings, integers, Booleans, floats, enumerations,
// handles or lists of handles. Read one of each and print the class of the property it returned.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT net, list;
upfPortDirE dir;
wire q;
leaf dut(q);
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  net = upf_get_handle_by_name("/top/VDD");
  $display("string=%s %s", kind(upf_query_object_properties(net, UPF_NAME)), text(net, UPF_NAME));
  $display("integer=%s %0d", kind(upf_query_object_properties(net, UPF_LINE)), number(net, UPF_LINE));
  $display("boolean=%s %0d", kind(upf_query_object_properties(upf_get_handle_by_name("/top/CORE.BAD"), UPF_IS_ILLEGAL)),
           number(upf_get_handle_by_name("/top/CORE.BAD"), UPF_IS_ILLEGAL));
  $display("float=%s %f", kind(upf_query_object_properties(upf_get_handle_by_name("/top/VDD.on1V"), UPF_VOLT_NOM)),
           upf_get_value_real(upf_query_object_properties(upf_get_handle_by_name("/top/VDD.on1V"), UPF_VOLT_NOM)));
  dir = upfPortDirE'(number(upf_get_handle_by_name("/top/PAD"), UPF_PORT_DIR));
  $display("enumerated=%s", dir.name());
  $display("handle=%s %s", kind(upf_query_object_properties(net, UPF_PARENT)), link(net, UPF_PARENT));
  list = upf_query_object_properties(upf_get_handle_by_name("/top/CORE"), UPF_FUNCTIONS);
  $display("list=%s", kind(list));
  $finish;
end
endmodule
