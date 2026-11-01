// CLAUSE: A system task returns nothing and may change its argument, and a system function returns a value of sizetf's width
// XFAIL: *
// vpi_register_systf from a startup table is unimplemented (docs/vpi.md), and the compiler rejects user system names as unknown.
// RUN: %clang -shared -fPIC %S/Inputs/36.5/probe.c -I%resource_dir/include -o %t.vpi.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.vpi.so -o %t.exe
// RUN: %t.exe
// CHECK: x=2
// CHECK: value=165 bits=8

module top;
  int x = 1;
  initial begin
    $bump(x);
    $display("x=%0d", x);
    $display("value=%0d bits=%0d", $sized(), $bits($sized()));
    $finish;
  end
endmodule
