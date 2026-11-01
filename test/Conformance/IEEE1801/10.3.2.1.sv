// CLAUSE: Unique object handles
// REQUIRES: upf
// XFAIL: *
// The UPF package has no information-model API (upfHandleT, upf_get_handle_by_name, 11.2.3), so the design cannot read this object.
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --upf %S/Inputs/10.3.2.1/design.upf -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK: nonnull=1{{$}}
// CHECK: distinct=1{{$}}
// CHECK: stable=1{{$}}
// CHECK: a=/top/first{{$}}
// CHECK: b=/top/second{{$}}

// 1801-2018 10.3.2.1, 11.2.2.1 NOTE 2: every object has a unique handle, and handles to objects can be
// compared for equality, so two lookups of one object agree and two objects differ.
module top;
import UPF::*;
upfHandleT a, b, again;
initial begin
  a = upf_get_handle_by_name("/top/first");
  b = upf_get_handle_by_name("/top/second");
  again = upf_get_handle_by_name("/top/first");
  $display("nonnull=%0d", a != upf_null && b != upf_null);
  $display("distinct=%0d", a != b);
  $display("stable=%0d", a == again);
  $display("a=%s", upf_query_object_pathname(a));
  $display("b=%s", upf_query_object_pathname(b));
  $finish;
end
endmodule
