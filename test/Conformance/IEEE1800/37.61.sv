// CLAUSE: Dynamic prefixing: h.x has class var h as vpiPrefix, and vpiHasActual follows the handle's current object
// XFAIL: *
// vpiLhs of h.x = 5 is null and no class property has a vpiPrefix: the runtime models vpiPrefix for method calls only.
// RUN: %clang -c -fPIC %S/Inputs/37.61/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// CHECK: with object: lhs=vpiIntVar value=5 prefix=vpiClassVar:h actual=1
// CHECK: null handle: lhs=vpiIntVar prefix=vpiClassVar:h actual=0

class C;
  int x;
endclass

module top;
C h;
import "DPI-C" context function void probe(input string when);
initial begin
  h = new;
  h.x = 5;
  probe("with object");
  h = null;
  probe("null handle");
  $finish;
end
endmodule
