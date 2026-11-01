// CLAUSE: division zero two state context
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int n,z,two; integer four;
initial begin
n=8; z=0; four=n/z+n; two=n/z+n; if(four!==32'bx || two!=0) $fatal(1,"four=%h two=%h",four,two);
$display("PASS"); $finish;
end
endmodule
