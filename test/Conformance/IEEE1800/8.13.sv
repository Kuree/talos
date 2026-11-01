// CLAUSE: Subclasses inherit members and may override methods; extending a final class is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.13/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: cannot extend 'B' because it is marked 'final'
// CHECK: inherited 1 1 added 2{{$}}
// CHECK-NEXT: overridden 20{{$}}
// CHECK-NEXT: base view 10 1{{$}}
// CHECK-NEXT: chain 7{{$}}
// CHECK-NEXT: final 6{{$}}

// 8.13: the clause's LinkedPacket; a non-virtual override follows the handle type, and :final bars only extension.
class Packet;
  int v = 1;
  function int get();
    return v;
  endfunction
  function int over();
    return 10;
  endfunction
endclass
class LinkedPacket extends Packet;
  LinkedPacket next;
  int w = 2;
  function LinkedPacket get_next();
    return next;
  endfunction
  function int over();
    return 20;
  endfunction
endclass
class :final TopPacket extends LinkedPacket;
  int z = 3;
endclass
module top;
  LinkedPacket d, e;
  Packet b;
  TopPacket t;
  initial begin
    d = new;
    e = new;
    d.next = e;
    e.v = 7;
    $display("inherited %0d %0d added %0d", d.v, d.get(), d.w);
    $display("overridden %0d", d.over());
    b = d;
    $display("base view %0d %0d", b.over(), b.get());
    $display("chain %0d", d.get_next().get());
    t = new;
    $display("final %0d", t.z + t.get() + t.w);
    $finish;
  end
endmodule
