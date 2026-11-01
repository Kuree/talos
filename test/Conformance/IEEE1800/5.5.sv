// CLAUSE: operator token
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

initial begin
if(1+2*3!=7)$fatal(1,"operator token");
$display("PASS");$finish;
end
endmodule
