// CLAUSE: Derived assertion statements finite witness
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// restrict property derives from assume property. A false assume is reported at ticks 1 and 3; the restrict on the
// same expression is not verified in simulation (16.14.4), so nothing else is printed and the exit status stays 0.
// CHECK-NOT: {{.}}
// CHECK: ASSUMED=0101
// CHECK-NOT: {{.}}

module top;
  bit clk, b; int t;
  bit [0:3] B = 4'b1010, ASSUMED;
  restrict property (@(posedge clk) b);
  assume property (@(posedge clk) b) else ASSUMED[t] = 1;
  initial begin
    for (t = 0; t < 4; t++) begin
      b = B[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("ASSUMED=%b", ASSUMED);
  end
endmodule
