// CLAUSE: overlap control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// A false antecedent passes vacuously at its own tick. |-> checks the consequent at the antecedent's end and
// |=> one tick later. Every match of the antecedent has to satisfy it: u@0 reaches v@2 with w false, so it fails.
// CHECK: OP=1101011 OF=0010100
// CHECK: NP=1002011 NF=0010010
// CHECK: MP=0111012 MF=0010000

module top;
  bit clk, a, b, u, v, w; int t;
  bit [0:6] A = 7'b0110100, B = 7'b1101001, U = 7'b1000100, V = 7'b0110011, W = 7'b0100011;
  bit [0:6][3:0] OP, OF, NP, NF, MP, MF;
  assert property (@(posedge clk) a |-> b) OP[t]++; else OF[t]++;
  assert property (@(posedge clk) a |=> b) NP[t]++; else NF[t]++;
  assert property (@(posedge clk) (u ##[1:2] v) |-> w) MP[t]++; else MF[t]++;
  initial begin
    for (t = 0; t < 7; t++) begin
      a = A[t]; b = B[t]; u = U[t]; v = V[t]; w = W[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("OP=%h OF=%h", OP, OF);
    $display("NP=%h NF=%h", NP, NF);
    $display("MP=%h MF=%h", MP, MF);
  end
endmodule
