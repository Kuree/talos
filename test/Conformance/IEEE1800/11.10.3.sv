// CLAUSE: empty string literal
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic[7:0]v="";
initial begin
if(v!==0||$bits("")!=8)$fatal(1,"empty string literal");
$display("PASS");$finish;
end
endmodule
