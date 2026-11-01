// CLAUSE: integer width sign
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
byte a=-1;byte unsigned b;
initial begin
b=a;if($bits(a)!=8||$bits(shortint)!=16||$bits(int)!=32||$bits(longint)!=64||a>=0||b!=255)$fatal(1,"integral type width or sign");
$display("PASS");$finish;
end
endmodule
