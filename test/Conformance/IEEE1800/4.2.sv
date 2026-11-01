// CLAUSE: continuous settles inactive
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a; wire [31:0] b=a+1;
initial begin
a=7; #0; if(b!=8) $fatal(1,"b=%0d",b); a=9; #0; if(b!=10) $fatal;
$display("PASS"); $finish;
end
endmodule
