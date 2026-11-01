// CLAUSE: Handles start null, alias on assignment and compare by object; handle arithmetic is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.4/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: invalid operand type 'C' to unary expression
// CHECK: uninitialized 1{{$}}
// CHECK-NEXT: constructed 1 1{{$}}
// CHECK-NEXT: alias 5 1{{$}}
// CHECK-NEXT: distinct 1 0{{$}}
// CHECK-NEXT: still held 5 1{{$}}

// 8.4: new makes a separate object, and assignment copies the handle, not the object.
class C;
  int v = 1;
endclass
module top;
  C a, b, c;
  task automatic make(inout C h);
    if (h == null) h = new;
  endtask
  initial begin
    $display("uninitialized %b", a == null);
    make(a);
    $display("constructed %b %0d", a != null, a.v);
    b = a;
    b.v = 5;
    $display("alias %0d %b", a.v, a == b);
    c = new;
    $display("distinct %0d %b", c.v, a == c);
    b = null;
    $display("still held %0d %b", a.v, b == null);
    $finish;
  end
endmodule
