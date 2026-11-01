// CLAUSE: self determined expression
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic[3:0]a=15;logic[5:0]b=10;logic[15:0]v;
initial begin
v={a*b};if(v!=22)$fatal(1,"self-determined multiply");
$display("PASS");$finish;
end
endmodule
