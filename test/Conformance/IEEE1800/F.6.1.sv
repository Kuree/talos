// CLAUSE: Extended Booleans finite witness
// XFAIL: *
// Rejected: the sequence method matched ("unsupported system call matched") and triggered on a sequence with local variables ("sequence event controls with local variables are not executable").
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// T(V).triggered is true at the end letter of a match, whichever attempt it came from; @(c)(T(V).matched) is true at
// the first tick of c after that end letter. Local variable x flows out through the argument.
// CHECK: T=01001000 M=00010010 L=00100000

module top;
  bit clk, slow, a, b; int d, q, t;
  bit [0:7] A = 8'b10010000, B = 8'b01001000, SLOW = 8'b00011011;
  int D[8] = '{5, 0, 0, 6, 0, 0, 0, 0};
  int Q[8] = '{0, 0, 5, 0, 0, 0, 0, 0};
  bit [0:7] T, M, L;
  sequence e1; @(posedge clk) a ##1 b; endsequence
  sequence e2(local output int x); @(posedge clk) (a, x = d) ##1 b; endsequence
  property p;
    int v;
    e2(v).triggered ##1 q == v;
  endproperty
  cover property (@(posedge clk) e1.triggered) T[t] = 1;
  cover property (@(posedge slow) e1.matched) M[t] = 1;
  cover property (@(posedge clk) p) L[t] = 1;
  initial begin
    for (t = 0; t < 8; t++) begin
      a = A[t]; b = B[t]; d = D[t]; q = Q[t];
      #1 slow = SLOW[t];
      #1 slow = 0; clk = 1;
      #1 clk = 0;
      #1;
    end
    $display("T=%b M=%b L=%b", T, M, L);
  end
endmodule
