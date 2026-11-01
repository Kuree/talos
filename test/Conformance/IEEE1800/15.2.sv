// CLAUSE: semaphore derived class
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 15.2: classes derived from semaphore and mailbox behave as the built-in classes (key counting, bounded FIFO).
// CHECK: SEM 1 1 0 1
// CHECK: MBX p3=0 num=2 r1=5 r2=6

class S extends semaphore;
  function new(int keys = 0); super.new(keys); endfunction
endclass
class M extends mailbox #(int);
  function new(int bound = 0); super.new(bound); endfunction
endclass
module top;
  S s;  M m;  int g1, g2, g3, g4, r1, r2, p3, n;
  initial begin
    s = new(2);
    g1 = s.try_get(1);  g2 = s.try_get(1);  g3 = s.try_get(1);  s.put(2);  g4 = s.try_get(2);
    $display("SEM %0d %0d %0d %0d", g1, g2, g3, g4);
    m = new(2);
    m.put(5);  m.put(6);  p3 = m.try_put(7);  n = m.num();
    m.get(r1);  m.get(r2);
    $display("MBX p3=%0d num=%0d r1=%0d r2=%0d", p3, n, r1, r2);
  end
endmodule
