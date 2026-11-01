// CLAUSE: property iff
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// All four operand combinations: implies is false only for 1,0 and iff is false when the operands differ.
// CHECK: IMP=1101 IMF=0010 IFP=1001 IFF=0110

module top;
  bit clk, a, b; int t;
  bit [0:3] A = 4'b0011, B = 4'b0101;
  bit [0:3][3:0] IMP, IMF, IFP, IFF;
  assert property (@(posedge clk) a implies b) IMP[t]++; else IMF[t]++;
  assert property (@(posedge clk) a iff b) IFP[t]++; else IFF[t]++;
  initial begin
    for (t = 0; t < 4; t++) begin
      a = A[t]; b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("IMP=%h IMF=%h IFP=%h IFF=%h", IMP, IMF, IFP, IFF);
  end
endmodule
