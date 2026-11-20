// RUN: talos -O3 --vpi=off %s -o %t && %t | FileCheck %s
// RUN: env TALOS_RT_GC_THRESHOLD=1 %t | FileCheck %s
// RUN: talos -O3 --two-state --vpi=off %s -o %t.two && %t.two | FileCheck %s
// RUN: talos -O0 --execution-tier=bytecode %s -o %t.bc && %t.bc | FileCheck %s
//
// A reference follows its element when a queue wraps and when growth moves
// its storage. A value copy keeps both original planes (1800-2023 7.10.3).
module top;
  typedef logic [7:0] element_t;
  typedef logic [15:0] pair_t;
  element_t q[$], saved[$];
  task automatic update(ref element_t item);
    q.push_front(8'had);
    item[3:0] = 4'b1zx0;
    if (q[1] !== {4'hb, 4'b1zx0}) $fatal(1, "ref write in short queue");
    if (pair_t'(q) !== {8'had, q[1]}) $fatal(1, "short queue bit stream");
    saved = q;
    q.push_back(8'h33);
    q.push_back(8'h44);
    q.push_back(8'h55);
    q.delete(0);
    item = 8'bx1z01001;
    if (q[0] !== item || q[1] !== 8'h33 || q[3] !== 8'h55)
      $fatal(1, "reference after queue growth");
    if (saved.size() != 2 || saved[1] !== {4'hb, 4'b1zx0})
      $fatal(1, "copy changed with the original");
  endtask
  task automatic pop_with_ref(ref element_t survivor);
    element_t old;
    old = q.pop_front();
    if (old !== 8'bx1z01001) $fatal(1, "popped planes");
    survivor = 8'b01zx1001;
    if (q[0] !== survivor) $fatal(1, "surviving ref after pop");
  endtask
  initial begin
    element_t head, tail0, tail1, tail2;
    q.push_back(8'hb1);
    update(q[0]);
    pop_with_ref(q[1]);
    q.push_front(8'h60);
    q.insert(1, 8'h61);
    q.delete(1);
    head = q.pop_front();
    if (head !== 8'h60 || q[0] !== 8'b01zx1001)
      $fatal(1, "wrapped prefix shift");
    tail0 = q.pop_back();
    tail1 = q.pop_back();
    tail2 = q.pop_back();
    if (tail0 !== 8'h55 || tail1 !== 8'h44 ||
        tail2 !== 8'b01zx1001 || q.size() != 0)
      $fatal(1, "wrapped suffix shift");
    head = q.pop_front();
    if (head !== element_t'('x) || q.size() != 0)
      $fatal(1, "empty pop default");
    $display("queue PASS");
    $finish;
  end
endmodule
// CHECK: queue PASS
