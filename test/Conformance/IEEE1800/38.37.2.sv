// CLAUSE: Routines in vlog_startup_routines run in order at startup, and the system tasks they register are callable from source and listed by vpiUserSystf
// XFAIL: *
// The table runs and vpiUserSystf lists the tasks, but the compiler does not know them: a call in source is "unknown system name" (docs/vpi.md: registration is not implemented).
// RUN: %clang -shared -fPIC %S/Inputs/38.37.2/probe.c -I%resource_dir/include -o %t.helper0.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.so -o %t.exe
// RUN: %t.exe
// CHECK: startup first
// CHECK-NEXT: startup second
// CHECK-NEXT: running
// CHECK-NEXT: listed $one
// CHECK-NEXT: listed $two
// CHECK-NEXT: calltf one
// CHECK-NEXT: calltf two

module top;
import "DPI-C" context function void list();
initial begin
  $display("running");
  list();
  $one;
  $two;
  $finish;
end
endmodule
