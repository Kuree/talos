// CLAUSE: vpi_register_systf returns a vpiUserSystf handle, and the source's system task then runs calltf with user_data on every call
// XFAIL: *
// A user-defined system task called from source is rejected at compile time (37.3.5).
// RUN: %clang -shared -fPIC %S/Inputs/38.37/probe.c -I%resource_dir/include -o %t.helper0.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.so -o %t.exe
// RUN: %t.exe
// CHECK: handle=vpiUserSystf
// CHECK-NEXT: calltf 1 user=tag
// CHECK-NEXT: between
// CHECK-NEXT: calltf 2 user=tag

module top;
import "DPI-C" context function void handle_type();
initial begin
  handle_type();
  $hello;
  $display("between");
  $hello;
  $finish;
end
endmodule
