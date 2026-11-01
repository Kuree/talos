// CLAUSE: Cell information
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.6.3.3/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: class=UPF_CELL{{$}}
// CHECK: kind=UPF_CELL_ISOLATION{{$}}
// CHECK: hdl=UPF_HDLCELL_COMB{{$}}
// CHECK: origin=UPF_ORIGIN_INSERTED{{$}}
// CHECK: source=/top/PD.ISO{{$}}

// 1801-2018 10.6.3.3 Example 1: an inferred isolation cell sits on the port it isolates, with the values
// in the table (whose isolation_cell is Table 32's UPF_CELL_ISOLATION), and names its strategy's extent.
module leaf(output logic port1);
  assign port1 = 1;
endmodule
module top;
import UPF::*;
upfHandleT h;
logic iso = 0;
wire port1;
leaf dut(port1);
upfCellKindE cell_kind;
upfHdlCellKindE hdl_kind;
upfCellOriginE origin;
function automatic upfHandleT at(string path); return upf_get_handle_by_name(path); endfunction
function automatic string kind(upfHandleT o); upfClassIdE c = upf_query_object_type(o); return c.name(); endfunction
function automatic int number(upfHandleT o, upfPropertyIdE p); return upf_get_value_int(upf_query_object_properties(o, p)); endfunction
function automatic string link(upfHandleT o, upfPropertyIdE p); return upf_query_object_pathname(upf_query_object_properties(o, p)); endfunction
initial begin
  h = upf_query_object_properties(at("/top/dut/port1"), UPF_CELL_INFO);
  $display("class=%s", kind(h));
  cell_kind = upfCellKindE'(number(h, UPF_CELL_KIND));
  hdl_kind = upfHdlCellKindE'(number(h, UPF_HDL_CELL_KIND));
  origin = upfCellOriginE'(number(h, UPF_CELL_ORIGIN));
  $display("kind=%s", cell_kind.name());
  $display("hdl=%s", hdl_kind.name());
  $display("origin=%s", origin.name());
  $display("source=%s", link(upf_iter_get_next(upf_query_object_properties(h, UPF_SOURCE_EXTENTS)), UPF_OBJECT));
  $finish;
end
endmodule
