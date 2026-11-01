// CLAUSE: vpi_put_userdata returns 1, replaces the value stored on a system task call, and returns 0 on failure
// XFAIL: *
// A user-defined system task called from source is rejected at compile time (37.3.5), so no call handle exists.
// RUN: %clang -shared -fPIC %S/Inputs/38.33/probe.c -I%resource_dir/include -o %t.helper0.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.so -o %t.exe
// RUN: %t.exe
// CHECK: first put=1 read=first
// CHECK-NEXT: second put=1 read=second
// CHECK-NEXT: bad handle put=0

module top;
initial begin $store; $finish; end
endmodule
