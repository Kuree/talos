// CLAUSE: Derived followed_by operators finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// r #-# p is not(r |-> not p) and r #=# p is not(r |=> not p). A false antecedent fails both forms of each pair.
// CHECK: OP=010000 OF=101111 EOP=010000 EOF=101111
// CHECK: NP=000100 NF=101102 ENP=000100 ENF=101102

module top;
  bit clk, a, b; int t;
  bit [0:5] A = 6'b011010, B = 6'b110100;
  bit [0:5][3:0] OP, OF, EOP, EOF, NP, NF, ENP, ENF;
  assert property (@(posedge clk) a #-# b) OP[t]++; else OF[t]++;
  assert property (@(posedge clk) not(a |-> not b)) EOP[t]++; else EOF[t]++;
  assert property (@(posedge clk) a #=# b) NP[t]++; else NF[t]++;
  assert property (@(posedge clk) not(a |=> not b)) ENP[t]++; else ENF[t]++;
  initial begin
    for (t = 0; t < 6; t++) begin
      a = A[t]; b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("OP=%h OF=%h EOP=%h EOF=%h", OP, OF, EOP, EOF);
    $display("NP=%h NF=%h ENP=%h ENF=%h", NP, NF, ENP, ENF);
  end
endmodule
