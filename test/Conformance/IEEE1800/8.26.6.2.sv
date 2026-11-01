// CLAUSE: A subclass override resolves inherited name collisions; an unresolved collision is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.26.6.2/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: 'T' in 'J' conflicts with another member already inherited from 'I'
// CHECK: 5{{$}}
// CHECK-NEXT: type 8{{$}}
// CHECK-NEXT: parameter 3{{$}}

// 8.26.6.2: even matching types collide, and the name then means the subclass's own declaration.
interface class PutImp #(type T = logic);
  pure virtual function void put(T a);
endclass
interface class GetImp #(type T = logic);
  pure virtual function T get();
endclass
interface class PutGetIntf #(type TYPE = logic)
    extends PutImp #(TYPE), GetImp #(TYPE);
  typedef TYPE T;
endclass
interface class A;
  parameter int N = 1;
endclass
interface class B;
  parameter int N = 2;
endclass
interface class K extends A, B;
  parameter int N = 3;
endclass
class Impl implements PutGetIntf #(int);
  int v;
  virtual function void put(int a);
    v = a;
  endfunction
  virtual function int get();
    return v + 1;
  endfunction
endclass
module top;
  Impl i;
  PutGetIntf #(int) h;
  initial begin
    i = new;
    h = i;
    h.put(4);
    $display("%0d", h.get());
    $display("type %0d", $bits(PutGetIntf#(byte)::T));
    $display("parameter %0d", K::N);
    $finish;
  end
endmodule
