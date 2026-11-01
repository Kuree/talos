// CLAUSE: Packed arrays are contiguous vectors with element selects; nonconstant bounds are rejected
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/7.4.1/variable.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/7.4.1/atom.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: reference to non-constant variable 'n' is not allowed in a constant expression
// DIAG: packed dimensions not allowed on predefined integer type 'int'
// CHECK: 11 44 2{{$}}
// CHECK-NEXT: vector 11223344 32{{$}}
// CHECK-NEXT: after write 1122aa44{{$}}
// CHECK-NEXT: signed -1 element 15 part 255{{$}}
// CHECK-NEXT: atom f ffff{{$}}

// 7.4.1: an ascending dimension puts element 0 at the MSB; only the whole signed vector reads as signed.
module top;
  bit [0:3][7:0] packedArray = 32'h11223344;
  logic signed [1:0][3:0] sv = 8'hff;
  byte c2 = -1;
  integer i1 = 32'hffff_0000;
  initial begin
    $display("%h %h %h", packedArray[0], packedArray[3], packedArray[1][7:4]);
    $display("vector %h %0d", packedArray, $bits(packedArray));
    packedArray[2] = 8'haa;
    $display("after write %h", packedArray);
    $display("signed %0d element %0d part %0d", sv, sv[0], sv[1:0]);
    $display("atom %h %h", c2[3:0], i1[31:16]);
    $finish;
  end
endmodule
