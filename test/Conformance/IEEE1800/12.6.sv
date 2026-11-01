// CLAUSE: pattern case named partial struct
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
typedef struct {int a,b,c;} S; S s; int out;
initial begin

s='{1,2,3};
case(s) matches
  '{b:.n,a:1}: out=n;
  default:out=0;
endcase
if(out!=2) $fatal(1,"out=%0d",out);

$display("PASS"); $finish;
end
endmodule
