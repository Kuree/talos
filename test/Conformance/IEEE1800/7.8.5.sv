// CLAUSE: assoc real key
// SINCE: 0.1.0
// RUN: %not %talos --std=1800-2023 --compile-threads=1 --top=top -O3 --execution-tier=%tier %s -o %t.exe
// CHECK-DAG: {{[eE][rR][rR][oO][rR]}}

module top;
int a[real];
initial begin
a[1.5]=7; a[2.5]=9; if(a.num()!=2 || a[1.5]!=7 || a[2.5]!=9) $fatal;
$display("PASS"); $finish;
end
endmodule
