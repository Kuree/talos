// CLAUSE: triage tolerance real static control
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

initial begin
if(!(6.0 inside {[7.0 +%- 25]})) $fatal;
$display("PASS"); $finish;
end
endmodule
