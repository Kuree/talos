// CLAUSE: realtoa roundtrip
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;string s;initial begin s.realtoa(1.25);if(s.atoreal()!=1.25)$fatal(1,"realtoa");$display("PASS");$finish;end endmodule
