// CLAUSE: atoreal illegal leading underscore
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 5.7: underscores, sized/based/signed literals, x/z digits, unbased unsized fill literals and real literal forms.
// CHECK: a=a5 b=1x0z c=15 d=-5
// CHECK: g=ff h=0000zzzz j=xxxx i=1000
// CHECK: e=2500.0 f=10.5

module top;
  logic [7:0] a = 8'hA_5, g = '1, h = 8'b0000_zzzz;  logic [3:0] b = 4'b1x0z, j = 'x;
  int c = 'o17, i = 1_000;  logic signed [7:0] d = -8'sd5;  real e = 2.5e3, f = 1_0.5;
  initial begin
    $display("a=%h b=%b c=%0d d=%0d", a, b, c, d);
    $display("g=%h h=%b j=%b i=%0d", g, h, j, i);
    $display("e=%0.1f f=%0.1f", e, f);
  end
endmodule
