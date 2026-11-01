// CLAUSE: property followed by
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Unlike implication, a false antecedent fails followed-by. #-# checks at the antecedent's end, #=# a tick later.
// CHECK: OP=010000 OF=101111
// CHECK: NP=000100 NF=101102

module top;
  bit clk, a, b; int t;
  bit [0:5] A = 6'b011010, B = 6'b110100;
  bit [0:5][3:0] OP, OF, NP, NF;
  assert property (@(posedge clk) a #-# b) OP[t]++; else OF[t]++;
  assert property (@(posedge clk) a #=# b) NP[t]++; else NF[t]++;
  initial begin
    for (t = 0; t < 6; t++) begin
      a = A[t]; b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("OP=%h OF=%h", OP, OF);
    $display("NP=%h NF=%h", NP, NF);
  end
endmodule
