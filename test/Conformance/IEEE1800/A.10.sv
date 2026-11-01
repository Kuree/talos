// CLAUSE: Footnote 14: automatic locals need a procedural context and data types may be omitted only after var
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/A.10/automatic.sv -o %t.bad.exe
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %S/Inputs/A.10/no_type.sv -o %t.bad.exe
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// DIAG: automatic variables can only be declared in procedural contexts
// DIAG: expected a declaration name
// CHECK: a=1 s=1{{$}}
// CHECK-NEXT: a=1 s=2{{$}}
// CHECK-NEXT: a=1 s=3{{$}}
// CHECK-NEXT: var 1 1{{$}}

// A.10 note 14: automatic is legal inside the task and restarts at each call, while static keeps counting.
module top;
  task t();
    automatic int a = 0;
    static int s = 0;
    a++;
    s++;
    $display("a=%0d s=%0d", a, s);
  endtask
  initial begin
    var v = 1'b1;
    t();
    t();
    t();
    $display("var %b %0d", v, $bits(v));
    $finish;
  end
endmodule
