// CLAUSE: Concatenation value, width and lvalue use; a select of a concatenation is not an lvalue
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/11.4.12/select.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/11.4.12/unsized.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: expression is not assignable
// DIAG: unsized integer in concat
// CHECK: 110100101 9{{$}}
// CHECK-NEXT: 1 0 1{{$}}
// CHECK-NEXT: 0 1 0{{$}}
// CHECK-NEXT: 01{{$}}

// 11.4.12: {p + q} is self-determined at 8 bits, so the select sees the low bits of the wrapped sum.
module top;
  logic a = 1, w = 0;
  logic [3:0] b = 4'b1010;
  logic log1, log2, log3;
  byte p = 8'hfe, q = 8'h03;
  bit [1:0] c;
  initial begin
    $display("%b %0d", {a, b[3:0], w, 3'b101}, $bits({a, b[3:0], w, 3'b101}));
    {log1, log2, log3} = 3'b101;
    $display("%b %b %b", log1, log2, log3);
    {log1, log2, log3} = {1'b0, 1'b1, 1'b0};
    $display("%b %b %b", log1, log2, log3);
    c = {p + q}[1:0];
    $display("%b", c);
    $finish;
  end
endmodule
