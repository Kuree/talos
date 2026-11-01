// CLAUSE: type operator identity
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
byte a; var type(a) b;
initial begin
a=7; b=9; if($bits(b)!=8 || b!=9) $fatal;
$display("PASS"); $finish;
end
endmodule
