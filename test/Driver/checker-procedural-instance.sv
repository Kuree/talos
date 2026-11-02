// RUN: rm -rf %t && mkdir -p %t
// RUN: cd %t && talos -O0 --execution-tier=native %s -o native && not ./native 2>/dev/null | FileCheck %s
// RUN: cd %t && talos -O0 --execution-tier=bytecode %s -o bytecode && not ./bytecode 2>/dev/null | FileCheck %s

// The example of IEEE 1800-2023 17.3, on ticks 15 and 25 and with en set from 12.
// Every instance has its own sum and its own p0, whichever was visited. check_inside
// queues p1, p2 and p3 when en holds, and check_loop queues three of each, with
// the value v1 had at each visit: 5 and 20 pass while 10 equals in1. At tick 5 sum is
// still unknown, which is what makes the simulation exit with an error.
checker c1(event clk, logic [7:0] a, b);
  logic [7:0] sum;
  always_ff @(clk) begin
    sum <= a + 1'b1;
    p0: assert property (sum != 8'hff) $display("%0t %m pass sum=%0d", $time, sum);
  end
  p1: assert property (@clk sum != 8'hff) $display("%0t %m pass sum=%0d", $time, sum);
  p2: assert property (@clk a != b) $display("%0t %m pass", $time);
      else $display("%0t %m fail", $time);
  p3: assert #0 (a != 8'hee) $display("%0t %m pass", $time);
endchecker
module top;
  bit clk, en;
  logic [7:0] in1 = 10, arr [0:20];
  initial foreach (arr[i]) arr[i] = i;
  c1 check_outside(posedge clk, in1, 8'd4);
  always @(posedge clk) begin
    automatic logic [7:0] v1 = 0;
    if (en) begin
      c1 check_inside(posedge clk, in1, v1);
    end
    for (int i = 0; i < 4; i++) begin
      v1 = v1 + 5;
      if (i != 2) begin
        c1 check_loop(posedge clk, in1, arr[v1]);
      end
    end
  end
  always #5 clk = ~clk;
  initial begin #12 en = 1; #4 $finish; end
endmodule
// CHECK-NOT: check_inside
// CHECK-DAG: 15 top.check_outside.p0 pass sum=11
// CHECK-DAG: 15 top.check_inside.p0 pass sum=11
// CHECK-DAG: 15 top.check_loop.p0 pass sum=11
// CHECK-DAG: 15 top.check_outside.p1 pass sum=11
// CHECK-DAG: 15 top.check_inside.p1 pass sum=11
// CHECK-DAG: 15 top.check_loop.p1 pass sum=11
// CHECK-DAG: 15 top.check_loop.p1 pass sum=11
// CHECK-DAG: 15 top.check_loop.p1 pass sum=11
// CHECK-DAG: 15 top.check_outside.p2 pass
// CHECK-DAG: 15 top.check_inside.p2 pass
// CHECK-DAG: 15 top.check_loop.p2 pass
// CHECK-DAG: 15 top.check_loop.p2 pass
// CHECK-DAG: 15 top.check_loop.p2 fail
// CHECK-DAG: 15 top.check_inside.p3 pass
// CHECK-DAG: 15 top.check_loop.p3 pass
// CHECK-DAG: 15 top.check_loop.p3 pass
// CHECK-DAG: 15 top.check_loop.p3 pass
