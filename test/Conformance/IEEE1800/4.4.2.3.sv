// CLAUSE: inactive before nba
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 4.4.2.3: #0 resumes in the Inactive region, after the Active events (A2) and before the NBA update (x is still 0).
// CHECK-DAG: A1
// CHECK-DAG: A2
// CHECK: I1 x=0
// CHECK: I2 x=0
// CHECK: N x=1

module top;
  int x;
  initial begin
    $display("A1");
    x <= 1;
    #0; $display("I1 x=%0d", x);
    #0; $display("I2 x=%0d", x);
    #1; $display("N x=%0d", x);
  end
  initial $display("A2");
endmodule
