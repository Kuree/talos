// CLAUSE: SystemVerilog UPF package
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.4/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: null=0{{$}}
// CHECK: bits=96 33 33 97 65{{$}}
// CHECK: class=UPF_SUPPLY_SET{{$}}
// CHECK: first=1{{$}}
// CHECK: name=primary{{$}}
// CHECK: real=0.500000{{$}}
// CHECK: set=FULL_ON{{$}}
// CHECK: partial=PARTIAL_ON{{$}}

// 1801-2018 11.2.4: the package's native structs have their declared widths, and its functions work on a
// real design: handles, iterator, values, conversions, and writes the package adds beside supply_on.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
upfIteratorT list;
upfSupplyObjT net;
upfBooleanObjT flag;
upfPowerStateObjT state;
upfPdSsObjT domain;
upfStateHolderObjT holder;
upfSupplyTypeT value;
wire q;
leaf dut(q);
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
initial begin
  $display("null=%0d", upf_null);
  $display("bits=%0d %0d %0d %0d %0d", $bits(net), $bits(flag), $bits(state), $bits(domain), $bits(holder));
  h = upf_get_handle_by_name("/top/PD.primary");
  $display("class=%s", kind(h));
  list = upf_query_object_properties(h, UPF_FUNCTIONS);
  $display("first=%0d", upf_iter_get_next(list) != upf_null);
  $display("name=%s", upf_get_value_str(upf_query_object_properties(h, UPF_NAME)));
  $display("real=%f", upf_convert_int_uvolts_to_real_volts(upf_convert_real_volts_to_int_uvolts(0.5)));
  void'(set_supply_state("/top/VDD", FULL_ON));
  void'(supply_partial_on("/top/VSS", 0.0));
  value = get_supply_value("/top/VDD");
  $display("set=%s", value.state.name());
  value = get_supply_value("/top/VSS");
  $display("partial=%s", value.state.name());
  $finish;
end
endmodule
