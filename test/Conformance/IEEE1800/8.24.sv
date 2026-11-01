// CLAUSE: Out-of-block methods bind to their prototypes; a signature mismatch is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.24/mismatch.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.24/twice.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: method argument 'n' is of type 'byte' which differs from 'int' given in its prototype
// DIAG: redefinition of 'C::f'
// CHECK: class return type 2.00{{$}}
// CHECK-NEXT: outer return type 1.50{{$}}
// CHECK-NEXT: default 6 10{{$}}
// CHECK-NEXT: qualifiers 2{{$}}

// 8.24: C::T is int, so 7.6 rounds to 8 and 8/3 divides as integers; the outer real T would print 2.53.
typedef real T;
class C;
  typedef int T;
  extern function T f();
  extern function real f2();
  extern static function int s(int a = 3);
  extern protected virtual function int send(int value);
  extern function int call_send(int v);
endclass
function C::T C::f();
  return 7.6;
endfunction
function real C::f2();
  return 1.5;
endfunction
function int C::s(int a);
  return a * 2;
endfunction
function int C::send(int value);
  return value + 1;
endfunction
function int C::call_send(int v);
  return send(v);
endfunction
module top;
  C c;
  real x;
  initial begin
    c = new;
    x = c.f() / 3;
    $display("class return type %0.2f", x);
    $display("outer return type %0.2f", c.f2());
    $display("default %0d %0d", C::s(), C::s(5));
    $display("qualifiers %0d", c.call_send(1));
    $finish;
  end
endmodule
