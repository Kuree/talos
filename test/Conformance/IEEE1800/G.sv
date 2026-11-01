// CLAUSE: Built-in classes
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins Annex G: the std:: package provides process, semaphore, mailbox and randomize, each used here with a compared result.
// CHECK: G sem=1,0,1 mbx=7 running=1 rnd=1

module top;
  std::semaphore sm = new(2);  std::mailbox #(int) mb = new;  std::process p;
  int r, v, g1, g2, g3;
  initial begin
    p = std::process::self();
    g1 = sm.try_get(2);  g2 = sm.try_get(1);  sm.put(2);  g3 = sm.try_get(2);
    mb.put(7);  mb.get(r);
    void'(std::randomize(v) with {v inside {[4:5]};});
    $display("G sem=%0d,%0d,%0d mbx=%0d running=%b rnd=%b", g1, g2, g3, r, p.status() == std::process::RUNNING, v >= 4 && v <= 5);
  end
endmodule
