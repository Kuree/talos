// CLAUSE: Handles of one class alias one object; other types are incompatible with class handles and chandles
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/6.22.5/to_class.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/6.22.5/from_class.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/6.22.5/chandle.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: value of type 'int' cannot be assigned to type 'C'
// DIAG: value of type 'C' cannot be assigned to type 'int'
// DIAG: value of type 'int' cannot be assigned to type 'chandle'
// CHECK: alias 8 equal 1{{$}}
// CHECK-NEXT: chandle null 1{{$}}

// 6.22.5 states only incompatibility; the legal half shows the same assignments work between matching handle types.
class C;
  int v = 3;
endclass
module top;
  C a, b;
  chandle h, k;
  initial begin
    a = new;
    b = a;
    b.v = 8;
    $display("alias %0d equal %b", a.v, a == b);
    h = k;
    $display("chandle null %b", h == null);
    $finish;
  end
endmodule
