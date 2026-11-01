// CLAUSE: Context of imported and exported tasks and functions
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.9.2/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins H.9.2: a context import sees the scope of the instance that declares it and calls the export of that same instance without svSetScope.
// CHECK-DAG: top.k1 who=top.k1 callex=11
// CHECK-DAG: top.k2 who=top.k2 callex=21

module kid #(parameter int P = 0);
  import "DPI-C" context function int callex(input int x);
  import "DPI-C" context function string who();
  export "DPI-C" function inc;
  function int inc(int x); return x + P; endfunction
  initial begin #1; $display("%m who=%s callex=%0d", who(), callex(1)); end
endmodule
module top;
  kid #(10) k1();  kid #(20) k2();
endmodule
