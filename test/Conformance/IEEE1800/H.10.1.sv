// CLAUSE: svdpi.h
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.10.1/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins H.10.1: svLogicVecVal aval/bval encode 0=(0,0) 1=(1,0) z=(0,1) x=(1,1), word 0 holds bits 31:0.
// CHECK: a0=f00100ff b0=f0f00000 a1=00000005 b1=00000000

module top;
  import "DPI-C" function void get(input logic [35:0] v, output int a0, output int b0, output int a1, output int b1);
  logic [35:0] v = {4'h5, 32'hx0z1_00ff};
  int a0, b0, a1, b1;
  initial begin
    get(v, a0, b0, a1, b1);
    $display("a0=%h b0=%h a1=%h b1=%h", a0, b0, a1, b1);
  end
endmodule
