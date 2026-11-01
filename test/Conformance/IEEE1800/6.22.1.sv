// CLAUSE: matching types
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

initial begin
if(type(byte signed)!=type(byte))$fatal(1,"matching default sign");
$display("PASS");$finish;
end
endmodule
