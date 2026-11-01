// CLAUSE: UPF design
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.3.6/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_DESIGN{{$}}
// CHECK-DAG: domain=/top/u1/PD{{$}}
// CHECK-DAG: domain=/top/u2/PD{{$}}
// CHECK: translation=FULL_ON{{$}}

// 1801-2018 10.6.3.6: the one design object holds global properties and lists every domain in the design,
// whichever scope made it. Its example nests the second domain; siblings avoid an unrelated limit.
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
wire a, b;
leaf u1(a), u2(b);
upfSupplyStateE translation;
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic void each(string key, upfHandleT list);
  for (upfHandleT h = upf_iter_get_next(list); h != upf_null; h = upf_iter_get_next(list))
    $display("%s=%s", key, upf_query_object_pathname(h));
endfunction
initial begin
  h = at("#UPFDESIGN#");
  $display("class=%s", kind(h));
  each("domain", upf_query_object_properties(h, UPF_POWER_DOMAINS));
  translation = upfSupplyStateE'(number(h, UPF_PARTIAL_ON_TRANSLATION));
  $display("translation=%s", translation.name());
  $finish;
end
endmodule
