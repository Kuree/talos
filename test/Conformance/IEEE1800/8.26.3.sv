// CLAUSE: Interface class types and parameters inherit by extends and need :: under implements; bare use is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.26.3/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: use of undeclared identifier 'T'
// CHECK: TWO 12{{$}}
// CHECK-NEXT: bits 2 8{{$}}
// CHECK-NEXT: 12 34{{$}}

// 8.26.3: the T2 widths show that extends carried the typedef with its parameter applied.
interface class IntfA #(type T1 = logic);
  typedef T1 [1:0] T2;
  pure virtual function T2 funcA();
endclass : IntfA
interface class IntfB #(type T = bit) extends IntfA #(T);
  pure virtual function T2 funcB();
endclass : IntfB
interface class IntfC;
  typedef enum {ONE, TWO, THREE} t1_t;
  parameter int N = 12;
  pure virtual function t1_t funcC();
endclass : IntfC
class ClassA implements IntfC;
  IntfC::t1_t t1_i = IntfC::TWO;
  virtual function IntfC::t1_t funcC();
    return t1_i;
  endfunction : funcC
endclass : ClassA
class ClassB implements IntfB #(bit [3:0]);
  virtual function IntfB #(bit [3:0])::T2 funcA();
    return 8'h12;
  endfunction
  virtual function IntfB #(bit [3:0])::T2 funcB();
    return 8'h34;
  endfunction
endclass
module top;
  ClassA a;
  ClassB b;
  IntfC c;
  initial begin
    a = new;
    c = a;
    $display("%s %0d", c.funcC().name(), IntfC::N);
    $display("bits %0d %0d", $bits(IntfA#()::T2), $bits(IntfB#(bit [3:0])::T2));
    b = new;
    $display("%h %h", b.funcA(), b.funcB());
    $finish;
  end
endmodule
