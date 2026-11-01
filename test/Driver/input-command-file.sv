// RUN: %split-file %s %t
// RUN: cd %t && talos -O0 design.sv -o sim && ./sim 2>&1 | FileCheck %S/input-command-file.sv

// IEEE 1800-2023 D.4: command text comes from a file and input then returns. A
// compiled simulation runs the commands that need no compiler and reports others.

// CHECK-DAG: hello{{[[:space:]]}}world
// CHECK-DAG: ab
// CHECK-DAG: warning: $input skipped a command a compiled simulation cannot run: force top.x = 1;
// CHECK-DAG: nested
// CHECK-DAG: warning: $input cannot read command file 'missing.txt'
// CHECK-DAG: after

//--- design.sv
module top;
  initial begin
    $input("commands.txt");
    $input("missing.txt");
    $display("after");
    $finish;
  end
endmodule
//--- commands.txt
// comment
$display("hello\tworld");
$write("a");

$write("b\n");
force top.x = 1;
$input("nested.txt");
//--- nested.txt
$display("nested");
