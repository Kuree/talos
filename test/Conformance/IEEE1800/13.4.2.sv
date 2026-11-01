// CLAUSE: recursive function
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
function automatic int f(int n);return n ? n*f(n-1) : 1;endfunction
initial begin
if(f(4)!=24)$fatal(1,"recursion");
$display("PASS");$finish;
end
endmodule
