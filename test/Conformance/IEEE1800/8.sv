// CLAUSE: Objects are built, read and dispatched through handles; a delay in a constructor is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: statements that pass time are not allowed in this context
// CHECK: 1 5{{$}}
// CHECK-NEXT: dispatch 14{{$}}
// CHECK-NEXT: shallow copy 7 made 3{{$}}

// Clause 8: constructor arguments, static members, virtual dispatch with super, and shallow copy, which skips new.
class Packet;
  int value;
  static int made = 0;
  function new(int v = 1);
    value = v;
    made++;
  endfunction
  virtual function int get();
    return value;
  endfunction
endclass
class Twice extends Packet;
  function new(int v);
    super.new(v);
  endfunction
  virtual function int get();
    return 2 * super.get();
  endfunction
endclass
module top;
  Packet p, q;
  Twice t;
  initial begin
    p = new;
    q = new(5);
    $display("%0d %0d", p.get(), q.get());
    t = new(7);
    p = t;
    $display("dispatch %0d", p.get());
    q = new p;
    $display("shallow copy %0d made %0d", q.value, Packet::made);
    $finish;
  end
endmodule
