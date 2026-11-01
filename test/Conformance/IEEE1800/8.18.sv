// CLAUSE: local and protected members are visible where specified; local and protected together are rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.18/both.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.18/outside.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.18/subclass.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.18/protected_outside.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: qualifier 'protected' cannot be used together with 'local' in a declaration
// DIAG: 'v' is a local member of 'C'
// DIAG: 'v' is a local member of 'C'
// DIAG: 'v' is a protected member of 'C'
// CHECK: other instance 1 0{{$}}
// CHECK-NEXT: inherited method 3{{$}}
// CHECK-NEXT: protected 5{{$}}

// 8.18: a local member reads across instances of its own class and through inherited methods, not from a subclass.
class Packet;
  local integer i;
  protected int p = 5;
  function new(int v);
    i = v;
  endfunction
  function integer compare(Packet other);
    compare = (this.i == other.i);
  endfunction
  function int read_i();
    return i;
  endfunction
endclass
class Sub extends Packet;
  function new(int v);
    super.new(v);
  endfunction
  function int read_p();
    return p;
  endfunction
endclass
module top;
  Packet a, b, c;
  Sub s;
  initial begin
    a = new(1);
    b = new(1);
    c = new(2);
    $display("other instance %0d %0d", a.compare(b), a.compare(c));
    s = new(3);
    $display("inherited method %0d", s.read_i());
    $display("protected %0d", s.read_p());
    $finish;
  end
endmodule
