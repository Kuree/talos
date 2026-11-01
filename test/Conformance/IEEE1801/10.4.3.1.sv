// CLAUSE: HDL relationships in the information model
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.4.3.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: scope=/top/dut{{$}}
// CHECK: element=/top/dut/mid{{$}}
// CHECK: control=UPF_HDL_NET_BIT /top/dut/iso{{$}}

// 1801-2018 10.4.3.1: HDL objects anchor relationships a) to c): the creation scope of a UPF object, the
// extent of its effective elements, and its control signals. Each is reached from the UPF side.
module inner(output logic q);
  assign q = 1;
endmodule
module leaf(output wire q);
  logic iso = 0;
  inner mid(q);
endmodule
module top;
import UPF::*;
wire q;
leaf dut(q);
upfHandleT strategy, sense;
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  strategy = upf_get_handle_by_name("/top/dut/PD.ISO");
  $display("scope=%s", link(strategy, UPF_CREATION_SCOPE));
  $display("element=%s", link(upf_query_object_properties(upf_get_handle_by_name("/top/dut/PD"), UPF_EFFECTIVE_EXTENTS),
                              UPF_HDL_ELEMENT));
  sense = upf_iter_get_next(upf_query_object_properties(strategy, UPF_ISOLATION_CONTROLS));
  $display("control=%s %s", kind(upf_query_object_properties(sense, UPF_CONTROL_SIGNAL)), link(sense, UPF_CONTROL_SIGNAL));
  $finish;
end
endmodule
