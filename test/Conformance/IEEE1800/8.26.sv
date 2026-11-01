// CLAUSE: Interface class handles dispatch to implementations and cast between types; data members are rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.26/property.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.26/new.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: member not allowed in interface class declaration
// DIAG: cannot create instance of interface class 'I'
// CHECK: implementer 1{{$}}
// CHECK-NEXT: implicit through superclass 2{{$}}
// CHECK-NEXT: second implementer 3{{$}}
// CHECK-NEXT: cast ok 1 g=4{{$}}
// CHECK-NEXT: cast fails 0{{$}}

// 8.26: the same handle type reaches three implementations, and $cast tests implements at run time.
interface class A;
  pure virtual function int f();
endclass
interface class A2;
  pure virtual function int g();
endclass
class B implements A;
  virtual function int f();
    return 1;
  endfunction
endclass
class C extends B;
  virtual function int f();
    return 2;
  endfunction
endclass
class D implements A, A2;
  virtual function int f();
    return 3;
  endfunction
  virtual function int g();
    return 4;
  endfunction
endclass
module top;
  A a;
  A2 a2;
  B b;
  C c;
  D d;
  initial begin
    b = new;
    a = b;
    $display("implementer %0d", a.f());
    c = new;
    a = c;
    $display("implicit through superclass %0d", a.f());
    d = new;
    a = d;
    $display("second implementer %0d", a.f());
    $display("cast ok %0d g=%0d", $cast(a2, a), a2.g());
    a = b;
    $display("cast fails %0d", $cast(a2, a));
    $finish;
  end
endmodule
