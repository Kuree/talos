// CLAUSE: boolean control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// A pending attempt at the end of the run: strong(s) has no match so it is false, while assert's implicit
// weak(s) has no finite prefix witnessing failure. A live mismatch fails all forms, and cover is strong.
// CHECK: P0=0100 F0=0020 PS=0100 FS=0020 PW=0100 FW=0020 C=0100
// CHECK-NOT: strong
// CHECK: strong failed at end
// CHECK-NOT: strong

module top;
  bit clk, a, b; int t;
  bit [0:3] A = 4'b1101, B = 4'b0100;
  bit [0:3][3:0] P0, F0, PS, FS, PW, FW, C;
  assert property (@(posedge clk) a ##1 b) P0[t]++;
    else if (t < 4) F0[t]++; else $fatal(1, "implicit weak failed at end");
  assert property (@(posedge clk) strong(a ##1 b)) PS[t]++;
    else if (t < 4) FS[t]++; else $display("strong failed at end");
  assert property (@(posedge clk) weak(a ##1 b)) PW[t]++;
    else if (t < 4) FW[t]++; else $fatal(1, "weak failed at end");
  cover property (@(posedge clk) a ##1 b) if (t < 4) C[t]++; else $fatal(1, "implicit strong cover passed at end");
  initial begin
    for (t = 0; t < 4; t++) begin
      a = A[t]; b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("P0=%h F0=%h PS=%h FS=%h PW=%h FW=%h C=%h", P0, F0, PS, FS, PW, FW, C);
  end
endmodule
