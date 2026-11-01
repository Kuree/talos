// CLAUSE: Replication joins copies and evaluates its operands once; a lone zero replication is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/11.4.12.1/zero.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/11.4.12.1/left.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/11.4.12.1/unknown.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: replication constant can only be zero inside of a concatenation
// DIAG: expression is not assignable
// DIAG: value must not have any unknown bits
// CHECK: 1111{{$}}
// CHECK-NEXT: 0101010{{$}}
// CHECK-NEXT: deadbeef 32{{$}}
// CHECK-NEXT: 9999 calls=1{{$}}
// CHECK-NEXT: 5a calls=2{{$}}

// 11.4.12.1: the operand of a replication runs once, even under a zero multiplier.
module top;
  parameter P = 32;
  logic [31:0] a = 32'hdeadbeef, b;
  logic w = 1, aa = 1, bb = 0;
  int calls = 0;
  logic [15:0] r;
  logic [7:0] s;
  function automatic logic [3:0] f(logic [3:0] v);
    calls++;
    return v;
  endfunction
  initial begin
    $display("%b", {4{w}});
    $display("%b", {bb, {3{aa, bb}}});
    b = {{32-P{1'b1}}, a[P-1:0]};
    $display("%h %0d", b, $bits({{32-P{1'b1}}, a[P-1:0]}));
    r = {4{f(4'h9)}};
    $display("%h calls=%0d", r, calls);
    s = {{0{f(4'h1)}}, 8'h5a};
    $display("%h calls=%0d", s, calls);
    $finish;
  end
endmodule
