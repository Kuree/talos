// CLAUSE: atoreal illegal leading underscore
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
string s="_1.5"; real r;
initial begin
r=s.atoreal(); if(r!=0.0) $fatal(1,"r=%g",r);
$display("PASS"); $finish;
end
endmodule
