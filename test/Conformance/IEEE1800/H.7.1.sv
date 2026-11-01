// CLAUSE: A multidimensional packed actual is linearized and normalized for an open array formal
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/H.7.1/illegal.sv -o %t.bad.exe
// RUN: %clang -c -fPIC %S/Inputs/H.7.1/dpi.c -I%resource_dir/include -o %t.dpi.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.dpi.o -o %t.exe
// RUN: %t.exe
// DIAG: 'C' is not a valid argument type in a DPI subroutine
// CHECK: packed 31 0 value 11223344{{$}}
// CHECK-NEXT: packed 7 0 unpacked 2 3 value 000000ab{{$}}

// H.7.1: bit [3:0][7:0] reaches C as one dimension [31:0], with or without an unpacked part.
module top;
  import "DPI-C" function void query(input bit [] b, output int left, right, value);
  import "DPI-C" function void query2(input bit [] b[], output int left, right, ul, ur, value);
  bit [3:0][7:0] actual = 32'h11223344;
  bit [1:0][3:0] arr[2:3] = '{8'hab, 8'hcd};
  int left, right, value, ul, ur;
  initial begin
    query(actual, left, right, value);
    $display("packed %0d %0d value %h", left, right, value);
    query2(arr, left, right, ul, ur, value);
    $display("packed %0d %0d unpacked %0d %0d value %h", left, right, ul, ur, value);
    $finish;
  end
endmodule
