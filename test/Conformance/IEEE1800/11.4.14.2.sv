// CLAUSE: Streaming re-orders blocks by slice size; a zero slice size is rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/11.4.14.2/illegal.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: value must be positive
// CHECK: ABCD{{$}}
// CHECK-NEXT: DCBA{{$}}
// CHECK-NEXT: CDAB{{$}}
// CHECK-NEXT: 10101100{{$}}
// CHECK-NEXT: 010111{{$}}
// CHECK-NEXT: 110101{{$}}
// CHECK-NEXT: 1110{{$}}

// 11.4.14.2: the clause's own examples, including the short last block of {<< 4 {6'b11_0101}}.
module top;
  int j = {"A", "B", "C", "D"};
  int r;
  logic [7:0] b8;
  logic [5:0] b6;
  logic [3:0] b4;
  initial begin
    r = {>> {j}};       $display("%s", r);
    r = {<< byte {j}};  $display("%s", r);
    r = {<< 16 {j}};    $display("%s", r);
    b8 = {<< {8'b0011_0101}};     $display("%b", b8);
    b6 = {<< 4 {6'b11_0101}};     $display("%b", b6);
    b6 = {>> 4 {6'b11_0101}};     $display("%b", b6);
    b4 = {<< 2 {{<< {4'b1101}}}}; $display("%b", b4);
    $finish;
  end
endmodule
