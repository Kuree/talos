// CLAUSE: real precedence
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
real r=1.5;
initial begin
if(r+2.0*3.0!=7.5)$fatal(1,"real precedence");
$display("PASS");$finish;
end
endmodule
