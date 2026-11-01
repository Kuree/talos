// CLAUSE: Level-shifter strategy
// REQUIRES: upf
// XFAIL: *
// set_level_shifter is not a registered UPF command, and the UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_LEVEL_SHIFTER_STRATEGY{{$}}
// CHECK: name=LS{{$}}
// CHECK: parent=/top/PD{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=5{{$}}
// CHECK: scope=/top{{$}}
// CHECK: applies=UPF_FILTER_INPUTS rule=UPF_LS_BOTH{{$}}
// CHECK: threshold=0.020000{{$}}
// CHECK: source=/top/PD.SSH1{{$}}
// CHECK: no_shift=0 force=0{{$}}

// 1801-2018 10.6.1.4: set_level_shifter makes this object, with the values in its example table.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
upfAppliesToFilterE applies;
upfLevelShifterRuleE rule;
wire q;
leaf dut(q);
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = at("/top/PD.LS");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $display("scope=%s", link(h, UPF_CREATION_SCOPE));
  applies = upfAppliesToFilterE'(number(h, UPF_APPLIES_TO));
  rule = upfLevelShifterRuleE'(number(h, UPF_LEVEL_SHIFT_RULE));
  $display("applies=%s rule=%s", applies.name(), rule.name());
  $display("threshold=%f", upf_get_value_real(upf_query_object_properties(h, UPF_THRESHOLD_VALUE)));
  $display("source=%s", link(h, UPF_SOURCE_FILTER));
  $display("no_shift=%0d force=%0d", number(h, UPF_IS_NO_SHIFT), number(h, UPF_IS_FORCE_SHIFT));
  $finish;
end
endmodule
