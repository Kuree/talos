// CLAUSE: An open array formal takes unpacked bounds from the actual and packed bounds from the import
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/H.6.1/class.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/H.6.1/packed.sv -o %t.bad.exe
// RUN: %clang -c -fPIC %S/Inputs/H.6.1/dpi.c -I%resource_dir/include -o %t.dpi.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.dpi.o -o %t.exe
// RUN: %t.exe
// DIAG: 'C' is not a valid argument type in a DPI subroutine
// DIAG: cannot be assigned to type 'bit[15:8]$[]'
// CHECK: up unpacked 2 5 packed 7 0 left elem 00000011{{$}}
// CHECK-NEXT: down unpacked 1 0 packed 7 0 left elem 00000055{{$}}

// H.6.1: the clause's bit [15:8] b [] called with two different unpacked ranges, which C sees as declared. Per H.7.5
// and H.7.6 the packed dimension reaches svLeft and svRight normalized, as [7:0].
module top;
  import "DPI-C" function void query(input bit [15:8] b[], output int ul, ur, pl, pr, first);
  bit [15:8] up[2:5] = '{8'h11, 8'h22, 8'h33, 8'h44};
  bit [15:8] down[1:0] = '{8'h55, 8'h66};
  int ul, ur, pl, pr, first;
  initial begin
    query(up, ul, ur, pl, pr, first);
    $display("up unpacked %0d %0d packed %0d %0d left elem %h", ul, ur, pl, pr, first);
    query(down, ul, ur, pl, pr, first);
    $display("down unpacked %0d %0d packed %0d %0d left elem %h", ul, ur, pl, pr, first);
    $finish;
  end
endmodule
