// CLAUSE: integer literal expression
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;

initial begin
if(3'd7+1!=8)$fatal(1,"unsized literal width");
$display("PASS");$finish;
end
endmodule
