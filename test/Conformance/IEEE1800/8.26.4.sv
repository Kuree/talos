// CLAUSE: interface class type restriction
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

interface class I;pure virtual function int f();endclass
module top;I i;initial i=new;endmodule
