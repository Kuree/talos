// CLAUSE: system call syntax
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

initial begin
if($bits(1)!=32)$fatal(1,"system function token");
$display("PASS");$finish;
end
endmodule
