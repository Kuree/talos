// CLAUSE: queue exam
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int status,n;
initial begin
$q_initialize(1,1,2,status);$q_add(1,5,7,status);$q_exam(1,1,n,status);if(status!=0 || n!=1)$fatal;
$display("PASS");$finish;
end
endmodule
