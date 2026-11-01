// CLAUSE: assoc exists
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[int];
initial begin
a[3]=1;if(!a.exists(3)||a.exists(4))$fatal(1,"associative exists");
$display("PASS");$finish;
end
endmodule
