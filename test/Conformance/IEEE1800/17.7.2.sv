// CLAUSE: checker assume randomization
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}
// CHECK-DAG: CHECK

checker c(input event clock);rand bit v;
a:assume property(@clock v==1);
b:assert property(@clock v==1)$display("CHECK");else $fatal;
endchecker
// A variable wider than a word, and an assumption disabled while it conflicts. A
// child's variable solved with the parent's has all of its assumptions (the parent
// sees u5 through m). An initialized variable holds its value in the first time
// step alone (17.7). An instance in a program solves ahead of Observed too.
checker forms(input bit clk, input bit rst);
  rand bit [99:0] wide;
  rand bit gated;
  rand bit [7:0] held = 8'h5a;
  w: assume property (@(posedge clk) wide[99:92] == 8'ha5 && wide[3:0] == 4'h9);
  d0: assume property (@(posedge clk) disable iff (rst) gated);
  d1: assume property (@(posedge clk) disable iff (!rst) !gated);
  bit started;
  always_ff @(posedge clk) started <= 1;
  i: assume property (@(posedge clk) !started || held != 8'h5a);
  bw: assert property (@(posedge clk) wide[99:92] == 8'ha5 && wide[3:0] == 4'h9) else $fatal(1, "wide");
  bh: assert property (@(posedge clk) $time != 0 || held == 8'h5a) else $fatal(1, "initialized");
  bn: assert property (@(posedge clk) !started || held != 8'h5a) else $fatal(1, "later step");
endchecker
checker outer(bit clk);
  checker inner(bit bclk, bit x);
    rand bit m;
    u1: assume property (@(posedge bclk) x == m);
    u5: assume property (@(posedge bclk) m == 1);
  endchecker
  rand bit q;
  inner b(clk, q);
endchecker
checker reader(input bit clk, input bit [7:0] s);
  rand bit [7:0] v;
  m: assume property (@(posedge clk) v == s);
endchecker
program p;
  reader r(top.clk2, top.s);
endprogram
module top;bit clk;bit clk2;bit rst;bit [7:0] s=1;c inst(posedge clk);forms f(clk2,rst);outer o(clk2);p u();
always #5 clk2=~clk2;always @(negedge clk2) begin s=s+1;rst=~rst;end
initial begin #0 clk2=1;#1;clk=1;#44;$display("PASS");$finish;end endmodule
