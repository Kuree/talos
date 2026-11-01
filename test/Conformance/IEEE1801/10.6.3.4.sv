// CLAUSE: Expression
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.3.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_EXPRESSION{{$}}
// CHECK: string=power == FULL_ON && ground == FULL_ON{{$}}
// CHECK-DAG: operand=/top/CORE.power{{$}}
// CHECK-DAG: operand=/top/CORE.ground{{$}}
// CHECK: before=0{{$}}
// CHECK: after=1{{$}}

// 1801-2018 10.6.3.4, Table 38: an expression keeps its text and operands, and its dynamic current value
// follows the operands. Its example's -logic_expr has no support yet, so a -supply_expr is used.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
wire q;
leaf dut(q);
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic void each(string key, upfHandleT list);
  for (upfHandleT h = upf_iter_get_next(list); h != upf_null; h = upf_iter_get_next(list))
    $display("%s=%s", key, upf_query_object_pathname(h));
endfunction
initial begin
  h = upf_query_object_properties(at("/top/CORE.ON"), UPF_SUPPLY_EXPR);
  $display("class=%s", kind(h));
  $display("string=%s", text(h, UPF_EXPR_STRING));
  each("operand", upf_query_object_properties(h, UPF_EXPR_OPERANDS));
  $display("before=%0d", number(h, UPF_CURRENT_VALUE));
  void'(supply_on("/top/VDD"));
  void'(supply_on("/top/VSS", 0.0));
  #1;
  $display("after=%0d", number(h, UPF_CURRENT_VALUE));
  $finish;
end
endmodule
