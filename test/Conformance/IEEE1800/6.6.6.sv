// CLAUSE: supply nets
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
supply0 ground; supply1 power;
initial begin
if(ground!==0||power!==1)$fatal(1,"supply values");
$display("PASS");$finish;
end
endmodule
