// CLAUSE: let named arguments
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
let add(x,y)=x+y;
initial begin
if(add(.y(5),.x(2))!=7)$fatal(1,"let named actuals");
$display("PASS");$finish;
end
endmodule
