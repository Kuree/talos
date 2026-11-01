// CLAUSE: assoc invalid index
// SINCE: 0.1.0
// RUN: %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// RUN: %t.exe
// CHECK-DAG: {{^PASS$}}

module top;
int a[int]='{default:7};
initial begin
a.delete(); if(a[0]!=7) $fatal(1,"actual=%0d",a[0]);
$display("PASS"); $finish;
end
endmodule
