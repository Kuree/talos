// CLAUSE: static task storage
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
task t(output int n);static int count=0;count++;n=count;endtask int a,b;
initial begin
t(a);t(b);if(a!=1||b!=2)$fatal(1,"static task persistence");
$display("PASS");$finish;
end
endmodule
