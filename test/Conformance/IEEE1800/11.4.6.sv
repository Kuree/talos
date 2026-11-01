// CLAUSE: wildcard equality asymmetric
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic [3:0] a,b;
initial begin
a=4'b10xz; b=4'b10??; if((a==?b)!==1 || (a!=?b)!==0) $fatal; a=4'bx001; b=4'b1001; if((a==?b)!==1'bx) $fatal; b=4'b1010; if((a==?b)!==0) $fatal;
$display("PASS"); $finish;
end
endmodule
