// CLAUSE: signed expression
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 11.7: $signed sign-extends, $unsigned reinterprets, and one unsigned operand makes a comparison unsigned.
// CHECK: s=-4 u=252 lt_mixed=0 lt_signed=1

module top;
  logic signed [7:0] s;  logic [7:0] u;  logic lt_u, lt_s;
  initial begin
    s = $signed(4'b1100);  u = $unsigned(s);
    lt_u = (-8'sd1 < 8'd1);  lt_s = ($signed(8'hff) < 8'sd1);
    $display("s=%0d u=%0d lt_mixed=%b lt_signed=%b", s, u, lt_u, lt_s);
  end
endmodule
