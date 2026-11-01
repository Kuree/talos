// CLAUSE: vlog_startup_routines registers a task and a function that the source can then call
// XFAIL: *
// vpi_register_systf from a startup table is unimplemented (docs/vpi.md), and the compiler rejects user system names as unknown.
// RUN: %clang -shared -fPIC %S/Inputs/36.9.1/probe.c -I%resource_dir/include -o %t.vpi.so
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --vpi=full -O3 --execution-tier=%tier %s %t.vpi.so -o %t.exe
// RUN: %t.exe
// CHECK: registered task=1 function=1
// CHECK: hello from task
// CHECK: answer=42

module top;
  int got;
  initial begin
    $hello;
    got = $answer();
    $display("answer=%0d", got);
    $finish;
  end
endmodule
