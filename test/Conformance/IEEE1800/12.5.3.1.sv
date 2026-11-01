// CLAUSE: unique no match warning
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{[wW][aA][rR][nN][iI][nN][gG]}}
// CHECK-DAG: {{^PASS$}}

module top;
int value=2; int result=0;
initial begin

  unique case(value) 0:result=1; 1:result=2; endcase
  #1;
  if(result!=0) $fatal(1,"unique no match changed result");

$display("PASS");
$finish;
end
endmodule
