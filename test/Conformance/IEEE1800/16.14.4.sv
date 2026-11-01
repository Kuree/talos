// CLAUSE: restrict statement
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// restrict is not verified in simulation and has no action block: ctr being 1 "is not an error". The assume on the
// same expression proves the ticks happened and the expression was false at ticks 1 and 3. There is no other output.
// CHECK-NOT: {{.}}
// CHECK: F=0101
// CHECK-NOT: {{.}}

module top;
  bit clk, ctr; int t;
  bit [0:3] C = 4'b0101, F;
  restrict property (@(posedge clk) ctr == 0);
  assume property (@(posedge clk) ctr == 0) else F[t] = 1;
  initial begin
    for (t = 0; t < 4; t++) begin
      ctr = C[t];
      #1 clk = 1;
      #1 clk = 0;
    end
    $display("F=%b", F);
  end
endmodule
