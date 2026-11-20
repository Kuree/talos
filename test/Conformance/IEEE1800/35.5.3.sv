// CLAUSE: Declaration scope and restoration in nested DPI context calls
// SINCE: 0.2.0
// RUN: %clang -c -fPIC %S/Inputs/35.5.3/export_same.c -I%resource_dir/include -o %t.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s %t.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

package pkg;
  timeunit 10ns/1ns;
  import "DPI-C" context function int probe(input int n, input string name);
  import "DPI-C" context function int nested(input int n);
  export "DPI-C" function local_id;
  function int local_id(); return nested(42); endfunction
endpackage

package top;
  timeunit 1ns/1ps;
  import "DPI-C" context function int distinct_package();
endpackage

module top;
  timeunit 1ns/1ps;
  for (genvar i = 0; i < 2; i++) begin : blk
    import "DPI-C" context function int probe(input int n, input string name);
    import "DPI-C" context function int nested(input int n);
    export "DPI-C" function local_id;
    function int local_id(); return nested(i); endfunction
  end

  initial begin
    if (!top::distinct_package()) $fatal(1, "package and instance scope names");
    if (!blk[1].probe(1, "top.blk[1]")) $fatal(1, "generate instance 1");
    if (!pkg::probe(42, "pkg")) $fatal(1, "package");
    if (!blk[0].probe(0, "top.blk[0]")) $fatal(1, "generate instance 0");
    $display("PASS");
  end
endmodule
