// CLAUSE: DPI C header
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/I/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins Annex I: the open-array query and element access routines report the actual SV range [2:5] and reach every element.
// CHECK: l=2 r=5 lo=2 hi=5 inc=-1 sz=4 dims=1 sum=100

module top;
  import "DPI-C" function void q(input int a[], output int l, output int r, output int lo, output int hi,
                                 output int inc, output int sz, output int dims, output int sum);
  int a[2:5] = '{10, 20, 30, 40};
  int l, r, lo, hi, inc, sz, dims, sum;
  initial begin
    q(a, l, r, lo, hi, inc, sz, dims, sum);
    $display("l=%0d r=%0d lo=%0d hi=%0d inc=%0d sz=%0d dims=%0d sum=%0d", l, r, lo, hi, inc, sz, dims, sum);
  end
endmodule
