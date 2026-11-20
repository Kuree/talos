// CLAUSE: A DPI context import reads the declaration's DPI properties through VPI
// SINCE: 0.2.0
// RUN: %clang -c -fPIC %S/Inputs/H.9.5/probe.c -I%resource_dir/include -o %t.o
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.o -o %t.exe
// RUN: %t.exe
// CHECK: {{^PASS$}}

module top;
  import "DPI-C" context check_properties = function int probe();
  import "DPI" pure twice = function int double_it(input int x);
  export "DPI-C" sv_identity = function identity;
  function int identity(input int x);
    return x;
  endfunction
  initial begin
    if (!probe() || double_it(4) != 8) $fatal(1, "DPI declaration properties");
    $display("PASS");
  end
endmodule
