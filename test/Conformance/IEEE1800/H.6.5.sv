// CLAUSE: Instant completion of imported functions
// SINCE: 0.1.0
// RUN: %clang -c -fPIC %S/Inputs/H.6.5/probe.c -I%resource_dir/include -o %t.helper0.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.helper0.o -o %t.exe
// RUN: %t.exe
// Pins H.6.5: a context import may call an exported SV function and query its scope; a noncontext import is a plain C call.
// CHECK: ctx=9 plain=9 name=top

module top;
  export "DPI-C" function ex;
  function int ex(int x); return x * 2; endfunction
  import "DPI-C" context function int ctx(input int x);
  import "DPI-C" function int plain(input int x);
  import "DPI-C" context function string ctxname();
  initial $display("ctx=%0d plain=%0d name=%s", ctx(4), plain(3), ctxname());
endmodule
