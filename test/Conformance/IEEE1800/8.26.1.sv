// CLAUSE: interface class syntax
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 8.26.1: a class implements an interface class that extends another, and calls dispatch through either interface handle.
// CHECK: f=1 g=2 via_i=1 via_j=1,2

interface class I; pure virtual function int f(); endclass
interface class J extends I; pure virtual function int g(); endclass
class C implements J;
  virtual function int f(); return 1; endfunction
  virtual function int g(); return 2; endfunction
endclass
module top;
  C c = new;  I i = c;  J j = c;
  initial $display("f=%0d g=%0d via_i=%0d via_j=%0d,%0d", c.f(), c.g(), i.f(), j.f(), j.g());
endmodule
