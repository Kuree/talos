// RUN: rm -rf %t && mkdir -p %t
// RUN: cd %t && talos -O0 --execution-tier=native %s -o native && ./native | FileCheck %s
// RUN: cd %t && talos -O0 --execution-tier=bytecode %s -o bytecode && ./bytecode | FileCheck %s

// IEEE 1800-2023 F.5 on nested properties, tick by tick. Ticks 0 to 5 have
// a=110100, b=011010, c=001100. Each line counts results per tick.
module top;
  bit clk, a, b, c; int t;
  bit [0:5] A = 6'b110100, B = 6'b011010, C = 6'b001100;
  bit [0:5][3:0] P1, F1, P2, F2, F3, P4, F4, P5, F5, F6, P7;
  // Nested implication: a then b, then c the tick after.
  assert property (@(posedge clk) a |-> (b |=> c)) P1[t]++; else F1[t]++;
  // Followed-by is the dual: failure without a match of a.
  assert property (@(posedge clk) (a #-# (b or c)) and (1'b1 |-> 1'b1)) P2[t]++; else F2[t]++;
  // not over a temporal property, in a consequent.
  assert property (@(posedge clk) a |-> not (##1 b)) else F3[t]++;
  // A property or: the left passes at once or the right must complete.
  assert property (@(posedge clk) c or (a |=> b)) P4[t]++; else F4[t]++;
  // if/else with temporal branches.
  assert property (@(posedge clk) a |-> if (b) ##1 c else ##1 b) P5[t]++; else F5[t]++;
  // Goto repetition in an antecedent with a nested implication.
  assert property (@(posedge clk) a ##1 b[->1] |-> (c |-> b)) else F6[t]++;
  // A vacuous success runs a cover's pass statement too (16.14.3).
  cover property (@(posedge clk) a |-> not (##1 b)) P7[t]++;
  initial begin
    for (t = 0; t < 6; t++) begin
      a = A[t]; b = B[t]; c = C[t];
      #1 clk = 1;
      #1 clk = 0;
      #1;
    end
    t = 5;
    $display("P1=%h F1=%h", P1, F1);
    $display("P2=%h F2=%h", P2, F2);
    $display("F3=%h", F3);
    $display("P4=%h F4=%h", P4, F4);
    $display("P5=%h F5=%h", P5, F5);
    $display("F6=%h", F6);
    $display("P7=%h", P7);
    $finish;
  end
endmodule

// CHECK: P1=102111 F1=000000
// CHECK: P2=010100 F2=101011
// CHECK: F3=011010
// CHECK: P4=012111 F4=000000
// CHECK: P5=012021 F5=000000
// CHECK: F6=000000
// CHECK: P7=001011
