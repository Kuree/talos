// CLAUSE: procedural assign rhs sensitivity
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 4.9.2: procedural assign tracks its RHS (B) and deassign leaves the last value (C).
// CHECK: A x=8
// CHECK: B x=10
// CHECK: C x=10

module top;
  reg [31:0] x;  int source;
  initial begin
    source = 7; assign x = source + 1; #1; $display("A x=%0d", x);
    source = 9; #1; $display("B x=%0d", x);
    deassign x; source = 11; #1; $display("C x=%0d", x);
  end
endmodule
