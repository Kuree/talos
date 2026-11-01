// CLAUSE: const values are set at run time, per call when automatic; writing one is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/6.20.6/value.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/6.20.6/handle.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: cannot assign to read-only variable 'x'
// DIAG: cannot assign to read-only variable 'h'
// CHECK: static 42{{$}}
// CHECK-NEXT: automatic 4{{$}}
// CHECK-NEXT: automatic 6{{$}}
// CHECK-NEXT: object 9{{$}}

// 6.20.6: a hierarchical name may set a static const, an automatic const is set per call, and a const handle
// keeps its object while the object's members stay writable.
class Obj;
  int m;
  function new(int v);
    m = v;
  endfunction
endclass
module sub;
  parameter int P = 6;
endmodule
module top;
  sub u();
  const int opt = u.P * 7;
  const Obj h = new(5);
  task automatic t(int v);
    const int c = v * 2;
    $display("automatic %0d", c);
  endtask
  initial begin
    $display("static %0d", opt);
    t(2);
    t(3);
    h.m = 9;
    $display("object %0d", h.m);
    $finish;
  end
endmodule
