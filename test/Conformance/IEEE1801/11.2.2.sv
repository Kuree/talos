// CLAUSE: Representation of property types in HDL
// REQUIRES: upf
// XFAIL: *
// add_supply_state is not a registered UPF command, and the UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/11.2.2/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: PAD 1 1 1.000000 UPF_DIR_IN{{$}}
// CHECK: iterator=1{{$}}
// CHECK: bits=32 32 32 1{{$}}

// 1801-2018 11.2.2.1 Table 35: each property type maps to an HDL type, handle and iterator being int.
// One value of each is held in a variable of its mapped type.
module top;
import UPF::*;
upfHandleT pad, it;
upfStringT name;
upfIntegerT line;
upfBooleanT in_set;
upfRealT nom;
upfPortDirE dir;
upfIteratorT functions;
initial begin
  pad = upf_get_handle_by_name("/top/PAD");
  name = upf_get_value_str(upf_query_object_properties(pad, UPF_NAME));
  line = upf_get_value_int(upf_query_object_properties(pad, UPF_LINE));
  in_set = upf_object_in_class(pad, UPF_PORT_CLASS);
  nom = upf_get_value_real(upf_query_object_properties(upf_get_handle_by_name("/top/PAD.on1V"), UPF_VOLT_NOM));
  dir = upfPortDirE'(upf_get_value_int(upf_query_object_properties(pad, UPF_PORT_DIR)));
  functions = upf_query_object_properties(upf_get_handle_by_name("/top/CORE"), UPF_FUNCTIONS);
  $display("%s %0d %0d %f %s", name, line, in_set, nom, dir.name());
  $display("iterator=%0d", upf_iter_get_next(functions) != upf_null);
  $display("bits=%0d %0d %0d %0d", $bits(upfHandleT), $bits(upfIteratorT), $bits(upfIntegerT), $bits(upfBooleanT));
  $finish;
end
endmodule
