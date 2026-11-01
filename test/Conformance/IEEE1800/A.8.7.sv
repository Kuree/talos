// CLAUSE: Signed hexadecimal literal
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins A.8.7: a signed hex literal is negative and sign-extends when widened, while the unsigned one zero-extends.
// CHECK: n=-128 w=ff80 u=0080

module top;
  logic signed [7:0] n = 8'sh80;  logic signed [15:0] w = 8'sh80;  logic [15:0] u = 8'h80;
  initial $display("n=%0d w=%h u=%h", n, w, u);
endmodule
