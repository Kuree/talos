// CLAUSE: Validity of handles: a handle stays valid until released or until its object ends, and releasing one leaves an equivalent handle valid
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/37.2.4/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: created n=7 same=1
// CHECK: later n=9
// CHECK: released first, second n=11
// CHECK: object member v=5 dynamic=1
// CHECK: object still alive v=6

module top;
class C; int v; endclass
int n = 7;
C owner, keep;
import "DPI-C" context function void create_handles();
import "DPI-C" context function void read_later();
import "DPI-C" context function void release_first();
import "DPI-C" context function void grab_member();
import "DPI-C" context function void read_member();
initial begin
  create_handles();
  #1 n = 9;
  read_later();
  release_first();
  #1 n = 11;
  read_later();
  owner = new;
  owner.v = 5;
  grab_member();
  // The object outlives this variable through `keep`, so the member's handle stays valid.
  keep = owner;
  owner = null;
  keep.v = 6;
  #1 read_member();
  $finish;
end
endmodule
