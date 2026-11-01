// CLAUSE: macro single unit shared
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top --single-unit -O3 --execution-tier=%tier %s %S/Inputs/3.13/second.sv -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`define VALUE 7
