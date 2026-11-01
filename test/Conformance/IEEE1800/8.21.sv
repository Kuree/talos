// CLAUSE: Pure virtual calls reach the implementing subclass; constructing an abstract class is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.21/construct.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.21/unimplemented.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: cannot create instance of virtual class 'A'
// DIAG: without providing an implementation for pure virtual method
// CHECK: dispatch 8{{$}}
// CHECK-NEXT: empty body x{{$}}

// 8.21: the abstract constructor runs only through the chain from a subclass, and an empty body returns x.
virtual class BasePacket;
  int base = 4;
  function new();
    base = 5;
  endfunction
  pure virtual function integer send(bit [31:0] data);
endclass
class EtherPacket extends BasePacket;
  virtual function integer send(bit [31:0] data);
    return data + base;
  endfunction
endclass
class EmptyPacket extends BasePacket;
  virtual function integer send(bit [31:0] data);
  endfunction
endclass
module top;
  BasePacket p;
  EtherPacket e;
  EmptyPacket v;
  initial begin
    e = new;
    p = e;
    $display("dispatch %0d", p.send(3));
    v = new;
    p = v;
    $display("empty body %0d", p.send(3));
    $finish;
  end
endmodule
