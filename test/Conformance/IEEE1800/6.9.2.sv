// CLAUSE: scalared vector
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
wire scalared[3:0] n;assign n=4'b1010;
initial begin
#1;if(n[1]!==1||n[3:2]!==2'b10)$fatal(1,"scalared select");
$display("PASS");$finish;
end
endmodule
