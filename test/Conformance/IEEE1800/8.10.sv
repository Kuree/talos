// CLAUSE: Static methods run without an instance and keep automatic locals; a static lifetime method is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.10/lifetime.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.10/nonstatic.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: class methods cannot have static lifetime
// DIAG: invalid use of non-static class property 'x'
// CHECK: no instance 1 2{{$}}
// CHECK-NEXT: null handle 3{{$}}
// CHECK-NEXT: property 3{{$}}
// CHECK-NEXT: automatic local 1{{$}}

// 8.10: a static method is not a method with static lifetime, so its local restarts at every call.
class id;
  static int current = 0;
  static function int next_id();
    next_id = ++current;
  endfunction
  static function int local_count();
    int v = 0;
    v++;
    return v;
  endfunction
endclass
module top;
  id a;
  initial begin
    $display("no instance %0d %0d", id::next_id(), id::next_id());
    $display("null handle %0d", a.next_id());
    $display("property %0d", id::current);
    void'(id::local_count());
    $display("automatic local %0d", id::local_count());
    $finish;
  end
endmodule
