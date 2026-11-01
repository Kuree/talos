// CLAUSE: Several local variable declarations nest, so a later initializer reads an earlier variable
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// (t1 v1 = e1; t2 v2 = e2; X) is (t1 v1 = e1; (t2 v2 = e2; X)): v2 is v1 + 1, captured when the attempt starts.
// CHECK: P=0101 F=0010

module top;
  bit clk; int d, q, t;
  int D[4] = '{1, 2, 3, 4};
  int Q[4] = '{0, 2, 0, 4};
  bit [0:3][3:0] P, F;
  property p;
    int v1 = d;
    int v2 = v1 + 1;
    ##1 q == v2;
  endproperty
  assert property (@(posedge clk) p) P[t]++; else if (t < 4) F[t]++;
  initial begin
    for (t = 0; t < 4; t++) begin
      d = D[t]; q = Q[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("P=%h F=%h", P, F);
  end
endmodule
