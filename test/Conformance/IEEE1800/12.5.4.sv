// CLAUSE: case inside asymmetric and range
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a,b;
initial begin

case(3'bx01) inside 3'b101:a=1; 3'b?01:a=2; default:a=3; endcase
case(5) inside [2:4]:b=1; [5:9]:b=2; default:b=3; endcase
if(a!=2 || b!=2) $fatal(1,"a=%0d b=%0d",a,b);

$display("PASS"); $finish;
end
endmodule
