// CLAUSE: A class may extend a base and implement interface classes together; implementing a concrete class is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.26.2/implement_class.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.26.2/extend_interface.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.26.2/interface_implements.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/8.26.2/interface_extends_class.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: cannot implement non-interface class 'B'
// DIAG: a normal (or virtual) class cannot extend interface class 'I'
// DIAG: expected ';'
// DIAG: an interface class cannot extend non-interface class 'B'
// CHECK: get 4 size 2{{$}}
// CHECK-NEXT: base method size 0{{$}}

// 8.26.2: the clause's Fifo, reached through each of its base and interface handles.
interface class PutImp #(type PUT_T = logic);
  pure virtual function void put(PUT_T a);
endclass
interface class GetImp #(type GET_T = logic);
  pure virtual function GET_T get();
endclass
class MyQueue #(type T = logic, int DEPTH = 1);
  T PipeQueue[$:DEPTH-1];
  virtual function void deleteQ();
    PipeQueue.delete();
  endfunction
endclass
class Fifo #(type T = logic, int DEPTH = 1)
    extends MyQueue #(T, DEPTH)
    implements PutImp #(T), GetImp #(T);
  virtual function void put(T a);
    PipeQueue.push_back(a);
  endfunction
  virtual function T get();
    get = PipeQueue.pop_front();
  endfunction
endclass
module top;
  Fifo #(int, 3) f;
  PutImp #(int) p;
  GetImp #(int) g;
  MyQueue #(int, 3) m;
  initial begin
    f = new;
    p = f;
    g = f;
    m = f;
    p.put(4);
    p.put(5);
    p.put(6);
    $display("get %0d size %0d", g.get(), f.PipeQueue.size());
    m.deleteQ();
    $display("base method size %0d", f.PipeQueue.size());
    $finish;
  end
endmodule
