// CLAUSE: A registered application overrides the built-in system function of the same name
// XFAIL: *
// vpi_register_systf from a startup table is unimplemented (docs/vpi.md), and the compiler rejects user system names as unknown.
// RUN: %clang -shared -fPIC %S/Inputs/36.3.2/probe.c -I%resource_dir/include -o %t.vpi.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.vpi.so -o %t.exe
// RUN: %t.exe
// CHECK: random=42
// CHECK: random=42
// 36.3.2: "the user-provided C application shall override the built-in", using its example of $random.

module top;
  initial begin
    $display("random=%0d", $random);
    $display("random=%0d", $random);
    $finish;
  end
endmodule
