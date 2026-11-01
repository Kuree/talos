// CLAUSE: Clock control finite witness
// XFAIL: *
// "or" and comma event expressions as an assertion clock are rejected: "AOT concurrent monitors currently require one direct signal edge clock".
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// One entry per time step. Each event is converted to a level as in the clause: posedge, negedge, edge, plain value
// change, "e iff b", "e1 or e2", "e1, e2", and a named event.
// CHECK: POS=0101000100 NEG=0010010001 EDGE=0111010101 ANY=0111010101
// CHECK: IFF=0100000100 OR=0111000110 COMMA=0111000110 EV=0000101000

module top;
  bit clk, en, other; event ev; int t;
  bit [0:9] C = 10'b0101100110, EN = 10'b1110000100, O = 10'b0011110011, E = 10'b0000101000;
  bit [0:9] POS, NEG, EDGE, ANY, IFF, OR, COMMA, EV;
  cover property (@(posedge clk) 1'b1) POS[t] = 1;
  cover property (@(negedge clk) 1'b1) NEG[t] = 1;
  cover property (@(edge clk) 1'b1) EDGE[t] = 1;
  cover property (@(clk) 1'b1) ANY[t] = 1;
  cover property (@(posedge clk iff en) 1'b1) IFF[t] = 1;
  cover property (@(posedge clk or posedge other) 1'b1) OR[t] = 1;
  cover property (@(posedge clk, posedge other) 1'b1) COMMA[t] = 1;
  cover property (@(ev) 1'b1) EV[t] = 1;
  initial begin
    for (t = 0; t < 10; t++) begin
      en = EN[t]; other = O[t]; clk = C[t];
      if (E[t]) -> ev;
      #1;
    end
    $display("POS=%b NEG=%b EDGE=%b ANY=%b", POS, NEG, EDGE, ANY);
    $display("IFF=%b OR=%b COMMA=%b EV=%b", IFF, OR, COMMA, EV);
  end
endmodule
