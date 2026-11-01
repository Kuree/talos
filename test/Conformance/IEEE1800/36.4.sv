// CLAUSE: A PLI application reads and writes the task/function arguments through VPI
// XFAIL: *
// vpi_register_systf from a startup table is unimplemented (docs/vpi.md), and the compiler rejects user system names as unknown.
// RUN: %clang -shared -fPIC %S/Inputs/36.4/probe.c -I%resource_dir/include -o %t.vpi.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.vpi.so -o %t.exe
// RUN: %t.exe
// CHECK: args=2
// CHECK: file=test_vector.pat
// CHECK: input_bus was 3
// CHECK: input_bus=200
// 36.4: "a number of PLI routines are provided that allow the PLI applications to read and write" the arguments.

module top;
  logic [7:0] input_bus = 3;
  initial begin
    $get_vector("test_vector.pat", input_bus);
    $display("input_bus=%0d", input_bus);
    $finish;
  end
endmodule
