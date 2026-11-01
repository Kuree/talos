// CLAUSE: Four-state, two-state, real, string and net values behave per type; a nonconstant range is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/6/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: reference to non-constant variable 'n' is not allowed in a constant expression
// CHECK: defaults xxxx 0000 0 x z{{$}}
// CHECK-NEXT: four to two 1x0z 1000{{$}}
// CHECK-NEXT: real to int 3{{$}}
// CHECK-NEXT: string 2 hi!
// CHECK-NEXT: signed byte -1{{$}}

// Clause 6: default values and conversions, which differ for each kind of type.
module top;
  logic [3:0] l;
  bit [3:0] b;
  int i;
  integer ig;
  wire w;
  real r = 2.5;
  string s = "hi";
  byte by = 8'hff;
  initial begin
    $display("defaults %b %b %0d %0d %b", l, b, i, ig, w);
    l = 4'b1x0z;
    b = l;
    $display("four to two %b %b", l, b);
    i = r;
    $display("real to int %0d", i);
    $display("string %0d %s", s.len(), {s, "!"});
    $display("signed byte %0d", by);
    $finish;
  end
endmodule
