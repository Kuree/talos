// CLAUSE: memory addressing
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic[7:0]m[2];int i=1;
initial begin
m[i]=8'ha5;if(m[i]!==8'ha5)$fatal(1,"memory address");
$display("PASS");$finish;
end
endmodule
