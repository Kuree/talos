// CLAUSE: Portability
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.7.3/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins H.7.3: an enum crosses as its int base type, integer and time as 4-state aval/bval words (xF -> aval ff, bval f0).
// CHECK: en=50 ia=000000ff ib=000000f0 t=2,1 tb1=0

module top;
  typedef enum {A = 3, B = 5} e_t;
  import "DPI-C" function int en(input e_t x);
  import "DPI-C" function void ti(input integer i, input time t, output int ia, output int ib, output int t0, output int t1, output int tb1);
  integer iv = 32'h0000_00xF;  time tv = {32'h1, 32'h2};  int ia, ib, t0, t1, tb1;
  initial begin
    ti(iv, tv, ia, ib, t0, t1, tb1);
    $display("en=%0d ia=%h ib=%h t=%0d,%0d tb1=%0d", en(B), ia, ib, t0, t1, tb1);
  end
endmodule
