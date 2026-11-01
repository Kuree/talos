// CLAUSE: Derived sequential property finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// R means strong(R) in cover and weak(R) in assert. On the same trace each pair reports alike, including the
// attempt left pending by the last tick, so a pass or fail action runs for both forms of a pair or for neither.
// CHECK: C=0100 CS=0100 P=0100 PW=0100 F=0020 FW=0020
// CHECK-NOT: cover pass at end
// CHECK-DAG: assert pass at end
// CHECK-DAG: weak pass at end
// CHECK-NOT: cover pass at end

module top;
  bit clk, a, b; int t;
  bit [0:3] A = 4'b1101, B = 4'b0100;
  bit [0:3][3:0] C, CS, P, PW, F, FW;
  cover property (@(posedge clk) a ##1 b) if (t < 4) C[t]++; else $display("cover pass at end");
  cover property (@(posedge clk) strong(a ##1 b)) if (t < 4) CS[t]++; else $display("cover pass at end");
  assert property (@(posedge clk) a ##1 b) if (t < 4) P[t]++; else $display("assert pass at end");
    else if (t < 4) F[t]++; else $fatal(1, "assert failed at end");
  assert property (@(posedge clk) weak(a ##1 b)) if (t < 4) PW[t]++; else $display("weak pass at end");
    else if (t < 4) FW[t]++; else $fatal(1, "weak failed at end");
  initial begin
    for (t = 0; t < 4; t++) begin
      a = A[t]; b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("C=%h CS=%h P=%h PW=%h F=%h FW=%h", C, CS, P, PW, F, FW);
  end
endmodule
