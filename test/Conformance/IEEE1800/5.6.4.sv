// CLAUSE: macro defaults
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`define ADD(a,b=2) ((a)+(b))
module top;
  initial begin
    if(`ADD(3,)!=5 || `ADD(3,4)!=7) $fatal(1,"macro defaults");
    $display("PASS"); $finish;
  end
endmodule
