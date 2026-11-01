// CLAUSE: wired logic resolution
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
wand a;wor b;assign a=0;assign a=1;assign b=0;assign b=1;
initial begin
#1;if(a!==0 || b!==1)$fatal;
$display("PASS");$finish;
end
endmodule
