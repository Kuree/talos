// CLAUSE: reduction four state known bits
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic [3:0] a,b;
initial begin
a=4'bx000; b=4'bx111; if((&a)!==0 || (|a)!==1'bx || (&b)!==1'bx || (|b)!==1 || (^a)!==1'bx) $fatal;
$display("PASS"); $finish;
end
endmodule
