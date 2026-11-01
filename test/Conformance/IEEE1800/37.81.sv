// CLAUSE: Time queue: pending times in increasing order through vpi_get_time, current time only before read-only sync, NULL when none remain
// XFAIL: *
// In a cbReadOnlySynch callback the iteration still returns the current time, with no event preceding it (detail 3) and when nothing is left (detail 2).
// RUN: %clang -c -fPIC %S/Inputs/37.81/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: NBA pending at 1: vpiTimeQueue=1, vpiTimeQueue=5, vpiTimeQueue=9,
// CHECK: read-only sync at 1: vpiTimeQueue=5, vpiTimeQueue=9, vpiTimeQueue=10,
// CHECK: read-only sync at 10: null
// CHECK: a=1 b=1 c=1

module top;
logic a, b, c;
import "DPI-C" context function void list_now();
import "DPI-C" context function void list_at_read_only_sync();
initial #9 b = 1;
initial #5 a = 1;
initial begin
  #1 c <= 1;
  list_now();
  list_at_read_only_sync();
  #9 list_at_read_only_sync();
end
final $display("a=%b b=%b c=%b", a, b, c);
endmodule
