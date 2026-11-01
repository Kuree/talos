// CLAUSE: continuous settles inactive
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 10.3: a chain of continuous assignments settles (Inactive region, after #0) with the new values.
// CHECK: A b=8 c=16
// CHECK: B b=10 c=20

module top;
  int a;  wire [31:0] b = a + 1;  wire [31:0] c = b * 2;
  initial begin
    a = 7; #0; $display("A b=%0d c=%0d", b, c);
    a = 9; #0; $display("B b=%0d c=%0d", b, c);
  end
endmodule
