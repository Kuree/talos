// CLAUSE: Implementing a parameterized interface class works; a type parameter or forward typedef base is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.26.4/implements_param.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.26.4/extends_param.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.26.4/forward.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: cannot extend or implement a type parameter
// DIAG: cannot extend or implement a type parameter
// DIAG: cannot extend or implement an incomplete forward typedef
// CHECK: implements 9{{$}}
// CHECK-NEXT: forward handle 11{{$}}

// 8.26.4: a forward typedef still serves as a handle type; only implementing or extending through one is barred.
interface class PutImp #(type T = logic);
  pure virtual function void put(T a);
endclass
class Fifo #(type T = int) implements PutImp #(T);
  T last;
  virtual function void put(T a);
    last = a;
  endfunction
endclass
typedef interface class Later;
class UsesLater;
  Later h;
endclass
interface class Later;
  pure virtual function int v();
endclass
class LaterImpl implements Later;
  virtual function int v();
    return 11;
  endfunction
endclass
module top;
  Fifo #(int) f;
  PutImp #(int) p;
  UsesLater u;
  LaterImpl l;
  initial begin
    f = new;
    p = f;
    p.put(9);
    $display("implements %0d", f.last);
    u = new;
    l = new;
    u.h = l;
    $display("forward handle %0d", u.h.v());
    $finish;
  end
endmodule
