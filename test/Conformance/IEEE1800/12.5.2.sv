// CLAUSE: constant case expression
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
logic[1:0]n=2'b10;int result;
initial begin
case(1'b1)n[1]:result=1;n[0]:result=2;endcase if(result!=1)$fatal(1,"constant case selector");
$display("PASS");$finish;
end
endmodule
