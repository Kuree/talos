// CLAUSE: Derived Boolean operators finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// All four operand combinations for each derived operator and its expansion.
// CHECK: IMP=1101 IMF=0010 IEP=1101 IEF=0010
// CHECK: IFP=1001 IFF=0110 FEP=1001 FEF=0110

module top;
  bit clk, a, b; int t;
  bit [0:3] A = 4'b0011, B = 4'b0101;
  bit [0:3][3:0] IMP, IMF, IEP, IEF, IFP, IFF, FEP, FEF;
  assert property (@(posedge clk) a implies b) IMP[t]++; else IMF[t]++;
  assert property (@(posedge clk) (not a) or b) IEP[t]++; else IEF[t]++;
  assert property (@(posedge clk) a iff b) IFP[t]++; else IFF[t]++;
  assert property (@(posedge clk) (a implies b) and (b implies a)) FEP[t]++; else FEF[t]++;
  initial begin
    for (t = 0; t < 4; t++) begin
      a = A[t]; b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("IMP=%h IMF=%h IEP=%h IEF=%h", IMP, IMF, IEP, IEF);
    $display("IFP=%h IFF=%h FEP=%h FEF=%h", IFP, IFF, FEP, FEF);
  end
endmodule
