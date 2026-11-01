// CLAUSE: class syntax
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// Pins 8.3: construction gives distinct objects with their own members; copying a handle aliases the same object.
// CHECK: null=1
// CHECK: n1=9 n2=4 same=1 distinct=0

class C; int n; endclass
module top;
  C c1, c2, c3;
  initial begin
    $display("null=%b", c1 == null);
    c1 = new;  c2 = new;  c1.n = 3;  c2.n = 4;  c3 = c1;  c3.n = 9;
    $display("n1=%0d n2=%0d same=%b distinct=%b", c1.n, c2.n, c1 == c3, c1 == c2);
  end
endmodule
