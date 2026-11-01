// CLAUSE: $getpattern optional interface
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic[1:0]m[1];wire a,b;assign {a,b}=$getpattern(m[0]);
initial begin
m[0]=2'b10;#1;if({a,b}!==2'b10)$fatal(1,"getpattern");
m[0]=2'bx1;#1;if({a,b}!==2'bx1)$fatal(1,"getpattern x");
m[0]=2'bz0;#1;if({a,b}!==2'bz0)$fatal(1,"getpattern z");
$display("PASS");$finish;
end
endmodule
