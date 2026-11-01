// CLAUSE: vpi_get_userdata returns NULL before any vpi_put_userdata, then the value stored on that system task call, across calls
// XFAIL: *
// A user-defined system task called from source is rejected at compile time (37.3.5), so no call handle exists.
// RUN: %clang -shared -fPIC %S/Inputs/38.14/probe.c -I%resource_dir/include -o %t.helper0.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.so -o %t.exe
// RUN: %t.exe
// CHECK: site 1 data=none count=1
// CHECK-NEXT: site 1 data=stored count=2
// CHECK-NEXT: site 2 data=none count=1

module top;
initial begin
  repeat (2) $tally(1);
  $tally(2);
  $finish;
end
endmodule
