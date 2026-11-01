// CLAUSE: Supply port state
// REQUIRES: upf
// XFAIL: *
// add_supply_state is not a registered UPF command, and the UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3).
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.1.16/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_SUPPLY_PORT_STATE{{$}}
// CHECK: name=on1V{{$}}
// CHECK: parent=/top/vdd{{$}}
// CHECK: file={{.*}}design.upf{{$}}
// CHECK: line=2{{$}}
// CHECK: scope=/top{{$}}
// CHECK: state=FULL_ON kind=NOM{{$}}
// CHECK: nom=1.000000{{$}}
// CHECK: listed=/top/vdd.on1V{{$}}

// 1801-2018 10.6.1.16: add_supply_state makes this object, with the values in its example table, and
// the port lists it in upf_sp_states.
module top;
import UPF::*;
upfHandleT h;
upfSupplyStateE state_value;
upfVoltKindE volt_kind;
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string text(upfHandleT o, upfPropertyIdE p); return upf_get_value_str(upf_query_object_properties(o, p)); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
function automatic void each(string key, upfHandleT list);
  for (upfHandleT h = upf_iter_get_next(list); h != upf_null; h = upf_iter_get_next(list))
    $display("%s=%s", key, upf_query_object_pathname(h));
endfunction
initial begin
  h = at("/top/vdd.on1V");
  $display("class=%s", kind(h));
  $display("name=%s", text(h, UPF_NAME));
  $display("parent=%s", link(h, UPF_PARENT));
  $display("file=%s", text(h, UPF_FILE));
  $display("line=%0d", number(h, UPF_LINE));
  $display("scope=%s", link(h, UPF_CREATION_SCOPE));
  state_value = upfSupplyStateE'(number(h, UPF_SUPPLY_STATE));
  volt_kind = upfVoltKindE'(number(h, UPF_VOLT_KIND));
  $display("state=%s kind=%s", state_value.name(), volt_kind.name());
  $display("nom=%f", upf_get_value_real(upf_query_object_properties(h, UPF_VOLT_NOM)));
  each("listed", upf_query_object_properties(at("/top/vdd"), UPF_SP_STATES));
  $finish;
end
endmodule
