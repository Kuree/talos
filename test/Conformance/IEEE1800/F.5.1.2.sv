// CLAUSE: Rewrite rules for properties finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// One entry per time step. c1 ticks at 1, 5, 9 with a sampled 1, 1, 0; c2 ticks at 3, 5, 7, 10 with b sampled 1, 1, 0,
// 1. The |-> consequent starts at the nearest c2 tick at or after the antecedent, the |=> one at the strictly later.
// CHECK: OP=000101000100 OF=000000000000
// CHECK: NP=000100000100 NF=000000010000

module top;
  bit c1, c2, a, b; int t;
  bit [0:11] C1 = 12'b010001000100, C2 = 12'b000101010010;
  bit [0:11] A = 12'b111111100000, B = 12'b111111000111;
  bit [0:11] OP, OF, NP, NF;
  assert property (@(posedge c1) a |-> @(posedge c2) b) OP[t] = 1; else OF[t] = 1;
  assert property (@(posedge c1) a |=> @(posedge c2) b) NP[t] = 1; else NF[t] = 1;
  initial begin
    for (t = 0; t < 12; t++) begin
      c1 = C1[t]; c2 = C2[t]; a = A[t]; b = B[t];
      #1;
    end
    $display("OP=%b OF=%b", OP, OF);
    $display("NP=%b NF=%b", NP, NF);
  end
endmodule
