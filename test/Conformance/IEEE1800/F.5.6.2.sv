// CLAUSE: Weak and strong satisfaction by finite words finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// With a local variable: v captures d when a is true and b must equal v on the next tick. A mismatch fails both forms.
// The attempt left pending by the last tick is false only for the strong form.
// CHECK: SP=0100 SF=0020 WP=0100 WF=0020
// CHECK-NOT: strong
// CHECK: strong failed at end
// CHECK-NOT: strong

module top;
  bit clk, a; int d, b, t;
  bit [0:3] A = 4'b1101;
  int D[4] = '{5, 6, 7, 8};
  int B[4] = '{0, 5, 0, 0};
  bit [0:3][3:0] SP, SF, WP, WF;
  property ps;
    int v;
    strong((a, v = d) ##1 b == v);
  endproperty
  property pw;
    int v;
    weak((a, v = d) ##1 b == v);
  endproperty
  assert property (@(posedge clk) ps) SP[t]++; else if (t < 4) SF[t]++; else $display("strong failed at end");
  assert property (@(posedge clk) pw) WP[t]++; else if (t < 4) WF[t]++; else $fatal(1, "weak failed at end");
  initial begin
    for (t = 0; t < 4; t++) begin
      a = A[t]; d = D[t]; b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("SP=%h SF=%h WP=%h WF=%h", SP, SF, WP, WF);
  end
endmodule
