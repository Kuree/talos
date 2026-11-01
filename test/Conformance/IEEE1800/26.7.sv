// CLAUSE: std qualified class
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
std::semaphore s;
initial begin
s=new(1);if(s.try_get(1)!=1 || s.try_get(1)!=0)$fatal;
$display("PASS");$finish;
end
endmodule
