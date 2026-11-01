// CLAUSE: Rewrite rules for sequences finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// One entry per time step. ##1 moves to the strictly later c2 tick (step 7 for the attempt at step 5, b false there),
// while ##0 moves there only if c1 and c2 do not tick together (16.13.1), so step 1 matches at 3 and step 5 at 5.
// CHECK: P=000100000000 F=000000010100
// CHECK: Z=000101000000

module top;
  bit c1, c2, a, b; int t;
  bit [0:11] C1 = 12'b010001000100, C2 = 12'b000101010010;
  bit [0:11] A = 12'b111111100000, B = 12'b111111000111;
  bit [0:11] P, F, Z;
  assert property (@(posedge c1) a ##1 @(posedge c2) b) P[t] = 1; else F[t] = 1;
  cover property (@(posedge c1) a ##0 @(posedge c2) b) Z[t] = 1;
  initial begin
    for (t = 0; t < 12; t++) begin
      c1 = C1[t]; c2 = C2[t]; a = A[t]; b = B[t];
      #1;
    end
    $display("P=%b F=%b", P, F);
    $display("Z=%b", Z);
  end
endmodule
