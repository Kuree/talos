// CLAUSE: macro paste quote
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

`define CAT(a,b) a``b
`define STR(a) `"a`"
`define SUM(a=3,b=4) ((a)+(b))
module top;
int xy;
initial begin
  `CAT(x,y)=9;
  if(xy!=9 || `STR(packet)!="packet" || `SUM()!=7 || `SUM(,5)!=8) $fatal;
  $display("PASS"); $finish;
end
endmodule
