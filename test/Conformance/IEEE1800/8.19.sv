// CLAUSE: Global and instance const class properties hold per-object values; writes outside new are rejected
// XFAIL: *
// compiler accepts a second assignment to an instance constant in its constructor, which 8.19 forbids
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.19/global.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.19/outside.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.19/twice.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: cannot assign to read-only variable 'v'
// DIAG: cannot assign to read-only variable 'v'
// CHECK: global 9216 9216{{$}}
// CHECK-NEXT: instance 100 200{{$}}

// 8.19: an instance const takes its value once in new, so two objects differ, and a global const never changes.
class Jumbo_Packet;
  const int max_size = 9 * 1024;
  byte payload[];
  function new(int size);
    payload = new[size > max_size ? max_size : size];
  endfunction
endclass
class Big_Packet;
  const int size;
  function new(int n);
    size = n;
  endfunction
endclass
module top;
  Jumbo_Packet j;
  Big_Packet a, b;
  initial begin
    j = new(10000);
    $display("global %0d %0d", j.max_size, j.payload.size());
    a = new(100);
    b = new(200);
    $display("instance %0d %0d", a.size, b.size);
    $finish;
  end
endmodule
