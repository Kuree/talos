// CLAUSE: event alias
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
event a,b;
initial begin
b=a;->a;if(!b.triggered)$fatal(1,"event alias");
$display("PASS");$finish;
end
endmodule
