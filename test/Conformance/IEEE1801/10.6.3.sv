// CLAUSE: Relationship objects
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: extent=UPF_EXTENT{{$}}
// CHECK: sense=UPF_SIGNAL_SENSE{{$}}
// CHECK: expr=UPF_EXPRESSION{{$}}
// CHECK: design=UPF_DESIGN{{$}}
// CHECK: relationship=1 1 0{{$}}

// 1801-2018 10.6.3: relationship objects link others. They are reached from what they relate, not by a
// design path, and are unnamed (upfBaseRelationshipT, not upfBaseNamedT).
module leaf(output logic q);
  assign q = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
logic iso = 0;
upfHandleT sense;
wire q;
leaf dut(q);
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
initial begin
  $display("extent=%s", kind(upf_query_object_properties(at("/top/PD"), UPF_EFFECTIVE_EXTENTS)));
  sense = upf_iter_get_next(upf_query_object_properties(at("/top/PD.ISO"), UPF_ISOLATION_CONTROLS));
  $display("sense=%s", kind(sense));
  h = upf_query_object_properties(at("/top/CORE.ON"), UPF_SUPPLY_EXPR);
  $display("expr=%s", kind(h));
  $display("design=%s", kind(at("#UPFDESIGN#")));
  $display("relationship=%0d %0d %0d", upf_object_in_class(sense, UPF_BASE_RELATIONSHIP), upf_object_in_class(h, UPF_BASE_RELATIONSHIP),
           upf_object_in_class(h, UPF_BASE_NAMED));
  $finish;
end
endmodule
