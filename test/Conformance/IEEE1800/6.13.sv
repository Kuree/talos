// CLAUSE: void function
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
function void put(output int v);v=3;endfunction int n;
initial begin
put(n);if(n!=3)$fatal(1,"void function");
$display("PASS");$finish;
end
endmodule
